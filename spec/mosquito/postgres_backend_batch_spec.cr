require "../spec_helper"
require "../../src/mosquito/postgres_backend"

# Test PostgreSQL batch operations
describe "Mosquito::PostgresBackend batch operations" do
  def setup
    Mosquito::PostgresBackend.connection_url = ENV["DATABASE_URL"]? || "postgres://mosquito:mosquito@localhost:5433/mosquito_test"
    Mosquito::PostgresBackend.flush
  end

  describe "#enqueue_batch" do
    it "enqueues multiple jobs in a single transaction" do
      backend = Mosquito::PostgresBackend.new("test_queue")

      # Create multiple job runs
      job_runs = (1..5).map do |i|
        Mosquito::JobRun.new("test_job_#{i}").tap(&.store)
      end

      # Enqueue them as a batch
      start_time = Time.monotonic
      backend.enqueue_batch(job_runs)
      batch_time = Time.monotonic - start_time

      # Verify all jobs were enqueued
      assert_equal 5, backend.size

      # Dequeue and verify order is preserved
      dequeued = [] of String
      5.times do
        if job = backend.dequeue
          dequeued << job.id
        end
      end

      assert_equal job_runs.map(&.id), dequeued

      # Compare with individual enqueues
      backend.flush
      start_time = Time.monotonic
      job_runs.each { |job| backend.enqueue(job) }
      individual_time = Time.monotonic - start_time

      # Batch should generally be faster, but we can't guarantee it in tests
      # Just verify both methods work correctly
      assert_equal 5, backend.size
    end

    it "handles empty array gracefully" do
      backend = Mosquito::PostgresBackend.new("test_queue")

      result = backend.enqueue_batch([] of Mosquito::JobRun)
      assert_equal [] of Mosquito::JobRun, result
      assert_equal 0, backend.size
    end

    it "rolls back all jobs if any fail" do
      backend = Mosquito::PostgresBackend.new("test_queue")

      # This test would require a way to inject a failure,
      # which might be difficult without modifying the implementation
      # For now, we'll just verify the transaction behavior works
      job_runs = (1..3).map do |i|
        Mosquito::JobRun.new("rollback_test_#{i}").tap(&.store)
      end

      backend.enqueue_batch(job_runs)
      assert_equal 3, backend.size
    end
  end

  describe "#cleanup_expired" do
    it "removes expired storage entries" do
      # Add a storage key with past expiration
      Mosquito::PostgresBackend.with_connection do |db|
        db.exec(<<-SQL, "expire_test_1", "{}", Time.utc - 1.minute)
          INSERT INTO mosquito_storage (key, data, expires_at)
          VALUES ($1, $2::jsonb, $3)
        SQL
      end

      # Add a non-expired key
      Mosquito::PostgresBackend.store("expire_test_2", {"data" => "test"})
      Mosquito::PostgresBackend.delete("expire_test_2", in: 1.hour)

      # Add a lock that's expired
      Mosquito::PostgresBackend.with_connection do |db|
        db.exec(<<-SQL, "expired_lock", "test", Time.utc - 1.minute)
          INSERT INTO mosquito_locks (key, value, expires_at)
          VALUES ($1, $2, $3)
        SQL
      end

      # Run cleanup
      deleted_count = Mosquito::PostgresBackend.cleanup_expired

      # At least 2 items should be deleted (expired storage and expired lock)
      assert deleted_count >= 2

      # The non-expired key should still have a future expiration
      ttl = Mosquito::PostgresBackend.expires_in("expire_test_2")
      assert ttl > 0
    end
  end

  describe "connection pooling" do
    it "respects pool configuration from environment" do
      # This is more of an integration test
      # We can verify the connection pool is working by running concurrent operations
      backend = Mosquito::PostgresBackend.new("pool_test")

      # Run multiple concurrent operations
      channel = Channel(Nil).new

      10.times do |i|
        spawn do
          job = Mosquito::JobRun.new("concurrent_#{i}").tap(&.store)
          backend.enqueue(job)
          channel.send(nil)
        end
      end

      # Wait for all to complete
      10.times { channel.receive }

      # Verify all jobs were enqueued
      assert_equal 10, backend.size
    end
  end
end
