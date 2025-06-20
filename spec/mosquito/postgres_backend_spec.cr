require "../spec_helper"
require "../../src/mosquito/postgres_backend"

# Set up test database URL for PostgresBackend
ENV["DATABASE_URL"] ||= "postgres://localhost/mosquito_test"

# Setup schema once at the beginning
begin
  DB.open(ENV["DATABASE_URL"]) do |db|
    # Test connection
    db.query_one("SELECT 1", as: Int32)

    # Read and execute the schema
    schema_path = File.join(__DIR__, "../../src/mosquito/postgres_backend/schema.sql")
    if File.exists?(schema_path)
      schema = File.read(schema_path)
      # Split by semicolons but be careful with functions that contain semicolons
      statements = [] of String
      current_statement = ""
      in_function = false

      schema.each_line do |line|
        if line.matches?(/CREATE\s+(OR\s+REPLACE\s+)?FUNCTION/i)
          in_function = true
        end

        current_statement += line + "\n"

        if in_function && line.strip.ends_with?("$$ LANGUAGE plpgsql;")
          in_function = false
          statements << current_statement.strip
          current_statement = ""
        elsif !in_function && line.strip.ends_with?(";")
          statements << current_statement.strip
          current_statement = ""
        end
      end

      statements.each do |statement|
        next if statement.empty?
        db.exec(statement) rescue nil # Ignore errors if schema already exists
      end
    end
  end
rescue ex
  puts "Warning: Could not setup schema: #{ex.message}"
end

describe Mosquito::PostgresBackend do
  # Clean up after each test
  def with_postgres_backend(&)
    original_backend = Mosquito.configuration.backend
    begin
      Mosquito.configure do |settings|
        settings.backend = Mosquito::PostgresBackend
      end
      Mosquito::PostgresBackend.connection_url = ENV["DATABASE_URL"]

      # Flush the database
      Mosquito.backend.flush

      yield
    ensure
      Mosquito.configure do |settings|
        settings.backend = original_backend
      end
    end
  end

  describe "storage operations" do
    it "stores and retrieves hash data" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"
          data = {"field1" => "value1", "field2" => "value2"}

          backend.store(key, data)
          retrieved = backend.retrieve(key)

          assert_equal data, retrieved
        end
      end
    end

    it "returns empty hash for non-existent key" do
      with_postgres_backend do
        clean_slate do
          assert_equal({} of String => String, backend.retrieve("non:existent"))
        end
      end
    end

    it "gets and sets individual fields" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"

          backend.set(key, "field1", "value1")
          assert_equal "value1", backend.get(key, "field1")

          backend.set(key, "field2", "value2")
          assert_equal "value2", backend.get(key, "field2")
          assert_equal "value1", backend.get(key, "field1")
        end
      end
    end

    it "returns nil for non-existent field" do
      with_postgres_backend do
        clean_slate do
          assert_nil backend.get("test:key", "non_existent")
        end
      end
    end

    it "sets multiple fields at once" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"
          values = {"field1" => "value1", "field2" => "value2", "field3" => nil}

          backend.set(key, values)

          assert_equal "value1", backend.get(key, "field1")
          assert_equal "value2", backend.get(key, "field2")
          assert_nil backend.get(key, "field3")
        end
      end
    end

    it "deletes fields" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"
          backend.set(key, "field1", "value1")
          backend.set(key, "field2", "value2")

          backend.delete_field(key, "field1")

          assert_nil backend.get(key, "field1")
          assert_equal "value2", backend.get(key, "field2")
        end
      end
    end

    it "increments numeric fields" do
      with_postgres_backend do
        clean_slate do
          key = "test:counter"

          # First increment creates the field
          assert_equal 1_i64, backend.increment(key, "count")
          assert_equal 2_i64, backend.increment(key, "count")
          assert_equal 12_i64, backend.increment(key, "count", by: 10)
        end
      end
    end

    it "deletes keys immediately" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"
          backend.set(key, "field", "value")

          backend.delete(key)

          assert_nil backend.get(key, "field")
        end
      end
    end

    it "schedules deletion with TTL" do
      with_postgres_backend do
        clean_slate do
          key = "test:key"
          backend.set(key, "field", "value")

          backend.delete(key, in: 2.seconds)

          # Key should still exist
          assert_equal "value", backend.get(key, "field")

          # Check expiration is set
          expires_in = backend.expires_in(key)
          assert expires_in > 0
          assert expires_in <= 2
        end
      end
    end
  end

  describe "queue operations" do
    getter job : QueuedTestJob { QueuedTestJob.new }
    getter queue_name : String { "test_queue_#{Random.rand(1000)}" }

    it "enqueues and dequeues jobs" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)
          job_run = job.build_job_run
          job_run.store

          queue.enqueue(job_run)

          dequeued = queue.dequeue
          assert_equal job_run.id, dequeued.not_nil!.id

          # Second dequeue should return nil
          assert_nil queue.dequeue
        end
      end
    end

    it "schedules jobs for future execution" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)
          job_run = job.build_job_run
          job_run.store

          future_time = 2.seconds.from_now
          queue.schedule(job_run, at: future_time)

          # Should not dequeue immediately
          assert_nil queue.dequeue

          # Should show in scheduled queue
          scheduled = queue.dump_scheduled_q
          assert_equal [job_run.id], scheduled
        end
      end
    end

    it "deschedules overdue jobs" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)
          job_run = job.build_job_run
          job_run.store

          past_time = Time.utc - 2.seconds
          queue.schedule(job_run, at: past_time)

          descheduled = queue.deschedule
          assert_equal 1, descheduled.size
          assert_equal job_run.id, descheduled.first.id

          # Should now be in waiting queue
          waiting = queue.dump_waiting_q
          assert_equal [job_run.id], waiting
        end
      end
    end

    it "finishes jobs by removing from pending" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)
          job_run = job.build_job_run
          job_run.store

          queue.enqueue(job_run)
          queue.dequeue

          # Should be in pending
          pending = queue.dump_pending_q
          assert_equal [job_run.id], pending

          queue.finish(job_run)

          # Should no longer be in pending
          pending = queue.dump_pending_q
          assert_empty pending
        end
      end
    end

    it "terminates jobs by moving to dead queue" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)
          job_run = job.build_job_run
          job_run.store

          queue.enqueue(job_run)
          queue.dequeue

          queue.terminate(job_run)

          # Should be in dead queue
          dead = queue.dump_dead_q
          assert_equal [job_run.id], dead

          # Should not be in pending
          pending = queue.dump_pending_q
          assert_empty pending
        end
      end
    end

    it "counts queue sizes" do
      with_postgres_backend do
        clean_slate do
          queue = backend.named(queue_name)

          assert_equal 0, queue.size

          # Add to waiting
          job_run1 = job.build_job_run
          job_run1.store
          queue.enqueue(job_run1)
          assert_equal 1, queue.size

          # Add to scheduled
          job_run2 = job.build_job_run
          job_run2.store
          queue.schedule(job_run2, at: 1.hour.from_now)
          assert_equal 2, queue.size

          # Move to pending
          queue.dequeue
          assert_equal 2, queue.size

          # Terminate (move to dead)
          queue.terminate(job_run1)
          assert_equal 2, queue.size
          assert_equal 1, queue.size(include_dead: false)
        end
      end
    end

    it "lists active queues" do
      with_postgres_backend do
        clean_slate do
          queue_names = ["queue1", "queue2", "queue3"]

          queue_names.each do |name|
            queue = backend.named(name)
            job_run = job.build_job_run
            job_run.store
            queue.enqueue(job_run)
          end

          listed = backend.list_queues
          assert_equal queue_names.sort, listed.sort
        end
      end
    end
  end

  describe "locking" do
    it "acquires and releases locks" do
      with_postgres_backend do
        clean_slate do
          key = "test:lock"
          value = "lock_holder_1"

          # Acquire lock
          assert backend.lock?(key, value, 5.seconds)

          # Same holder can re-acquire
          assert backend.lock?(key, value, 5.seconds)

          # Different holder cannot acquire
          refute backend.lock?(key, "different_holder", 5.seconds)

          # Release lock
          backend.unlock(key, value)

          # Now different holder can acquire
          assert backend.lock?(key, "different_holder", 5.seconds)
        end
      end
    end

    it "expires locks after TTL" do
      with_postgres_backend do
        clean_slate do
          key = "test:lock"
          value = "lock_holder"

          # Acquire lock with very short TTL
          assert backend.lock?(key, value, 100.milliseconds)

          # Wait for expiration
          sleep 0.2.seconds

          # Different holder should now be able to acquire
          assert backend.lock?(key, "new_holder", 5.seconds)
        end
      end
    end
  end

  describe "pub/sub" do
    it "publishes and receives messages" do
      with_postgres_backend do
        clean_slate do
          channel_name = "test:channel"
          message = "test message"

          received = nil
          subscriber = backend.subscribe(channel_name)

          spawn do
            received = subscriber.receive
          end

          # Give subscriber time to set up
          sleep 0.5.seconds

          backend.publish(channel_name, message)

          # Wait for message
          sleep 0.5.seconds

          assert received, "No message was received"
          if msg = received
            assert_equal channel_name, msg.channel
            assert_equal message, msg.message
          end

          subscriber.close
        end
      end
    end
  end

  describe "overseer management" do
    it "registers and lists overseers" do
      with_postgres_backend do
        clean_slate do
          overseer_ids = ["overseer1", "overseer2", "overseer3"]

          overseer_ids.each do |id|
            backend.register_overseer(id)
          end

          listed = backend.list_overseers
          assert_equal overseer_ids.sort, listed.sort
        end
      end
    end
  end

  describe "flush operation" do
    it "clears all data" do
      with_postgres_backend do
        clean_slate do
          # Add various data
          backend.set("key1", "field", "value")

          queue = backend.named("test_queue")
          job_run = QueuedTestJob.new.build_job_run
          job_run.store
          queue.enqueue(job_run)

          backend.register_overseer("test_overseer")

          # Flush everything
          backend.flush

          # Verify everything is gone
          assert_nil backend.get("key1", "field")
          assert_empty backend.list_queues
          assert_empty backend.list_overseers
          assert_equal 0, queue.size
        end
      end
    end
  end
end
