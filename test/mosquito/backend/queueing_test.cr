require "../../test_helper"

describe "Backend Queues" do
  let(:backend_name) { "test#{rand(1000)}" }
  getter queue : Mosquito::Backend { backend.named backend_name }

  let(:job) { QueuedTestJob.new }
  getter task : Mosquito::Task { Mosquito::Task.new("mock_task") }

  describe "queue_names" do
    it "builds a waiting queue" do
      assert_equal "mosquito:waiting:#{backend_name}", queue.waiting_q
    end

    it "builds a scheduled queue" do
      assert_equal "mosquito:scheduled:#{backend_name}", queue.scheduled_q
    end

    it "builds a pending queue" do
      assert_equal "mosquito:pending:#{backend_name}", queue.pending_q
    end

    it "builds a dead queue" do
      assert_equal "mosquito:dead:#{backend_name}", queue.dead_q
    end
  end

  describe "list_queues" do
    def fill_queues
      names = %w|test1 test2 test3 test4|

      names[0..3].each do |queue_name|
        backend.named(queue_name).enqueue task
      end

      backend.named(names.last).schedule task, at: 1.second.from_now
    end

    def fill_uncounted_queues
      names = %w|test5 test6 test7 test8|

      names[0..3].each do |queue_name|
        backend.named(queue_name).tap do |q|
          q.enqueue task
          q.dequeue
        end
      end

      backend.named(names.last).terminate task
    end

    it "can get a list of available queues" do
      clean_slate do
        fill_queues
        assert_equal %w|test1 test2 test3 test4|, backend.list_queues.sort
      end
    end

    it "de-dups the queue list" do
      clean_slate do
        fill_queues
        assert_equal %w|test1 test2 test3 test4|, backend.list_queues.sort
      end
    end

    it "includes queues prefixed with scheduled and waiting but not pending or dead" do
      clean_slate do
        fill_queues
        fill_uncounted_queues

        assert_equal %w|test1 test2 test3 test4|, backend.list_queues.sort
      end
    end
  end

  describe "schedule" do
    it "adds a task to the schedule_q at the time" do
      clean_slate do
        timestamp = 2.seconds.from_now
        task = job.build_task
        queue.schedule task, at: timestamp
        assert_equal timestamp.to_unix_ms.to_s, queue.scheduled_task_time task
      end
    end
  end

  describe "deschedule" do
    it "returns a task if it's due" do
      clean_slate do
        run_time = Time.utc - 2.seconds
        task = job.build_task
        task.store
        queue.schedule task, at: run_time

        overdue_tasks = queue.deschedule
        assert_equal [task], overdue_tasks
      end
    end

    it "returns a blank array when no tasks exist" do
      clean_slate do
        overdue_tasks = queue.deschedule
        assert_empty overdue_tasks
      end
    end

    it "doesn't return tasks which aren't yet due" do
      clean_slate do
        run_time = Time.utc + 2.seconds
        task = job.build_task
        task.store
        queue.schedule task, at: run_time

        overdue_tasks = queue.deschedule
        assert_empty overdue_tasks
      end
    end
  end

  describe "enqueue" do
    it "puts a task on the waiting_q" do
      clean_slate do
        task = job.build_task
        queue.enqueue task
        waiting_tasks = queue.dump_waiting_q
        assert_equal [task.id], waiting_tasks
      end
    end
  end

  describe "dequeue" do
    it "returns a task object when one is waiting" do
      clean_slate do
        task = job.build_task
        task.store
        queue.enqueue task
        waiting_task = queue.dequeue
        assert_equal task, waiting_task
      end
    end

    it "moves the task from waiting to pending" do
      clean_slate do
        task = job.build_task
        task.store
        queue.enqueue task
        waiting_task = queue.dequeue
        pending_tasks = queue.dump_pending_q
        assert_equal [task.id], pending_tasks
      end
    end

    it "returns nil when nothing is waiting" do
      clean_slate do
        assert_equal nil, queue.dequeue
      end
    end

    it "returns nil when a task is queued but not stored" do
      clean_slate do
        task = job.build_task
        # task.store # explicitly don't store this one
        queue.enqueue task
        waiting_task = queue.dequeue
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
        queue.enqueue task
        waiting_task = queue.dequeue
        assert_equal task, waiting_task

        # now finish it
        queue.finish task

        pending_tasks = queue.dump_pending_q
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
        queue.enqueue task
        waiting_task = queue.dequeue
        assert_equal task, waiting_task

        # now terminate it
        queue.terminate task

        dead_tasks = queue.dump_dead_q
        assert_equal [task.id], dead_tasks
      end
    end
  end

end
