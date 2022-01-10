require "../../test_helper"

describe Mosquito::RedisBackend do
  let(:redis) { Mosquito::Redis.instance }
  let(:backend_name) { "test#{rand(1000)}" }
  let(:backend) { RedisBackend.named backend_name }
  let(:location) { "location-#{rand(1000)}" }
  let(:sample_data) { { "test" => "#{rand(1000)}" } }

  let(:job) { TestJobs::Queued.new }

  describe "queue_names" do
    it "builds a waiting queue" do
      assert_equal "mosquito:waiting:#{backend_name}", backend.waiting_q
    end

    it "builds a scheduled queue" do
      assert_equal "mosquito:scheduled:#{backend_name}", backend.scheduled_q
    end

    it "builds a pending queue" do
      assert_equal "mosquito:pending:#{backend_name}", backend.pending_q
    end

    it "builds a dead queue" do
      assert_equal "mosquito:dead:#{backend_name}", backend.dead_q
    end
  end

  describe "hash storage" do
    it "can store and retrieve" do
      backend.store location, sample_data
      retrieved_data = backend.retrieve location
      assert_equal sample_data, retrieved_data
    end
  end

  describe "delete" do
    it "deletes immediately" do
      backend.store location, sample_data
      backend.delete location
      blank_data = {} of String => String
      assert_equal blank_data, backend.retrieve(location)
    end

    it "deletes at a ttl" do
      # Since redis is outside the control of timecop, this test is just showing
      # that #delete can be called with a ttl and we trust redis to do it's job.
      backend.store location, sample_data
      backend.delete location, in: 1.second
    end
  end

  describe "list_queues" do
    it "can get a list of available queues" do
      clean_slate do
        redis.set "mosquito:waiting:test1", 1
        redis.set "mosquito:waiting:test2", 1
        redis.set "mosquito:scheduled:test3", 1

        assert_equal ["test1", "test2", "test3"], backend.class.list_queues.sort
      end
    end

    it "de-dups the queue list" do
      clean_slate do
        redis.set "mosquito:waiting:test1", 1
        redis.set "mosquito:scheduled:test1", 1

        assert_equal ["test1"], backend.class.list_queues.sort
      end
    end

    it "includes queues prefixed with scheduled and waiting but not pending or dead" do
      clean_slate do
        redis.set "mosquito:waiting:test1", 1
        redis.set "mosquito:scheduled:test2", 1
        redis.set "mosquito:pending:test3", 1
        redis.set "mosquito:dead:test4", 1

        assert_equal ["test1", "test2"], backend.class.list_queues.sort
      end
    end
  end

  describe "self.flush" do
    it "wipes the database" do
      clean_slate do
        redis.set "key", 1
        backend.class.flush
        assert_nil redis.get "key"
      end
    end
  end

  describe "#flush" do
    it "empties the queues" do
      clean_slate do
        redis.lpush backend.waiting_q, "test"
        redis.lpush backend.scheduled_q, "test"
        redis.lpush backend.pending_q, "test"
        redis.lpush backend.dead_q, "test"

        backend.flush
        empty_set = [] of String

        assert_equal empty_set, backend.dump_waiting_q
        assert_equal empty_set, backend.dump_scheduled_q
        assert_equal empty_set, backend.dump_pending_q
        assert_equal empty_set, backend.dump_dead_q
      end
    end

    it "but doesn't truncate the database" do
      clean_slate do
        redis.set "key", "value"
        backend.flush
        assert_equal "value", redis.get "key"
      end
    end
  end

  describe "schedule" do
    it "adds a task to the schedule_q at the time" do
      clean_slate do
        timestamp = 2.seconds.from_now
        task = job.build_task
        backend.schedule task, at: timestamp
        assert_equal timestamp.to_unix_ms.to_s, backend.scheduled_task_time task
      end
    end
  end

  describe "deschedule" do
    it "returns a task if it's due" do
      clean_slate do
        run_time = Time.utc - 2.seconds
        task = job.build_task
        task.store
        backend.schedule task, at: run_time

        overdue_tasks = backend.deschedule
        assert_equal [task], overdue_tasks
      end
    end

    it "returns a blank array when no tasks exist" do
      clean_slate do
        overdue_tasks = backend.deschedule
        assert_empty overdue_tasks
      end
    end

    it "doesn't return tasks which aren't yet due" do
      clean_slate do
        run_time = Time.utc + 2.seconds
        task = job.build_task
        task.store
        backend.schedule task, at: run_time

        overdue_tasks = backend.deschedule
        assert_empty overdue_tasks
      end
    end
  end

  describe "enqueue" do
    it "puts a task on the waiting_q" do
      clean_slate do
        task = job.build_task
        backend.enqueue task
        waiting_tasks = backend.dump_waiting_q
        assert_equal [task.id], waiting_tasks
      end
    end
  end

  describe "dequeue" do
    it "returns a task object when one is waiting" do
      clean_slate do
        task = job.build_task
        task.store
        backend.enqueue task
        waiting_task = backend.dequeue
        assert_equal task, waiting_task
      end
    end

    it "moves the task from waiting to pending" do
      clean_slate do
        task = job.build_task
        task.store
        backend.enqueue task
        waiting_task = backend.dequeue
        pending_tasks = backend.dump_pending_q
        assert_equal [task.id], pending_tasks
      end
    end

    it "returns nil when nothing is waiting" do
      clean_slate do
        assert_equal nil, backend.dequeue
      end
    end

    it "returns nil when a task is queued but not stored" do
      clean_slate do
        task = job.build_task
        # task.store # explicitly don't store this one
        backend.enqueue task
        waiting_task = backend.dequeue
        assert_nil waiting_task
      end
    end
  end

  describe "finish" do
    it "removes the task from the pending queue" do
      clean_slate do
        task = job.build_task
        task.store

        # first move the task from waiting to pending
        backend.enqueue task
        waiting_task = backend.dequeue
        assert_equal task, waiting_task

        # now finish it
        backend.finish task

        pending_tasks = backend.dump_pending_q
        assert_empty pending_tasks
      end
    end
  end

  describe "terminate" do
    it "adds a task to the dead queue" do
      clean_slate do
        task = job.build_task
        task.store

        # first move the task from waiting to pending
        backend.enqueue task
        waiting_task = backend.dequeue
        assert_equal task, waiting_task

        # now terminate it
        backend.terminate task

        dead_tasks = backend.dump_dead_q
        assert_equal [task.id], dead_tasks
      end
    end
  end

  describe "size" do
    it "returns the size of the named q" do
      clean_slate do
        task = job.build_task
        task.store

        redis.lpush "mosquito:waiting:#{backend_name}", "waiting_item"
        redis.lpush "mosquito:pending:#{backend_name}", "pending_item"
        redis.zadd "mosquito:scheduled:#{backend_name}", 1, "scheduled_item"
        redis.lpush "mosquito:dead:#{backend_name}", "dead_item"

        assert_equal 4, backend.size
      end
    end

    it "returns the size of the named q (without the dead_q)" do
      clean_slate do
        task = job.build_task
        task.store

        redis.lpush "mosquito:waiting:#{backend_name}", "waiting_item"
        redis.lpush "mosquito:pending:#{backend_name}", "pending_item"
        redis.lpush "mosquito:pending:#{backend_name}", "pending_item2"
        redis.zadd "mosquito:scheduled:#{backend_name}", 1, "scheduled_item"
        redis.lpush "mosquito:dead:#{backend_name}", "dead_item"
        redis.lpush "mosquito:dead:#{backend_name}", "dead_item2"

        assert_equal 4, backend.size(include_dead: false)
      end
    end
  end

end
