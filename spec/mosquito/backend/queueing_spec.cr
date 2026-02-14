require "../../spec_helper"

describe "Backend Queues" do
  getter backend_name : String { "test#{rand(1000)}" }
  getter queue : Mosquito::Backend::Queue { backend.queue backend_name }

  getter job : QueuedTestJob { QueuedTestJob.new }
  getter job_run : Mosquito::JobRun { Mosquito::JobRun.new("mock_job_run") }

  describe "list_queues" do
    def fill_queues
      names = %w|test1 test2 test3 test4|

      names[0..3].each do |queue_name|
        backend.queue(queue_name).enqueue job_run
      end

      backend.queue(names.last).schedule job_run, at: 1.second.from_now
    end

    def fill_uncounted_queues
      names = %w|test5 test6 test7 test8|

      names[0..3].each do |queue_name|
        backend.queue(queue_name).tap do |q|
          q.enqueue job_run
          q.dequeue
        end
      end

      backend.queue(names.last).terminate job_run
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
  end

  describe "schedule" do
    it "adds a job_run to the schedule_q at the time" do
      clean_slate do
        timestamp = 2.seconds.from_now
        job_run = job.build_job_run
        queue.schedule job_run, at: timestamp
        assert_equal Time.unix_ms(timestamp.to_unix_ms), queue.scheduled_job_run_time job_run
      end
    end
  end

  describe "deschedule" do
    it "returns a job_run if it's due" do
      clean_slate do
        run_time = Time.utc - 2.seconds
        job_run = job.build_job_run
        job_run.store
        queue.schedule job_run, at: run_time

        overdue_job_runs = queue.deschedule
        assert_equal [job_run], overdue_job_runs
      end
    end

    it "returns a blank array when no job_runs exist" do
      clean_slate do
        overdue_job_runs = queue.deschedule
        assert_empty overdue_job_runs
      end
    end

    it "doesn't return job_runs which aren't yet due" do
      clean_slate do
        run_time = Time.utc + 2.seconds
        job_run = job.build_job_run
        job_run.store
        queue.schedule job_run, at: run_time

        overdue_job_runs = queue.deschedule
        assert_empty overdue_job_runs
      end
    end
  end

  describe "enqueue" do
    it "puts a job_run on the waiting_q" do
      clean_slate do
        job_run = job.build_job_run
        queue.enqueue job_run
        waiting_job_runs = queue.list_waiting
        assert_equal [job_run.id], waiting_job_runs
      end
    end
  end

  describe "dequeue" do
    it "returns a job_run object when one is waiting" do
      clean_slate do
        job_run = job.build_job_run
        job_run.store
        queue.enqueue job_run
        waiting_job_run = queue.dequeue
        assert_equal job_run, waiting_job_run
      end
    end

    it "moves the job_run from waiting to pending" do
      clean_slate do
        job_run = job.build_job_run
        job_run.store
        queue.enqueue job_run
        waiting_job_run = queue.dequeue
        pending_job_runs = queue.list_pending
        assert_equal [job_run.id], pending_job_runs
      end
    end

    it "returns nil when nothing is waiting" do
      clean_slate do
        assert_equal nil, queue.dequeue
      end
    end

    it "returns nil when a job_run is queued but not stored" do
      clean_slate do
        job_run = job.build_job_run
        # job_run.store # explicitly don't store this one
        queue.enqueue job_run
        waiting_job_run = queue.dequeue
        assert_nil waiting_job_run
      end
    end
  end

  describe "finish" do
    it "removes the job_run from the pending queue" do
      clean_slate do
        job_run = job.build_job_run
        job_run.store

        # first move the job_run from waiting to pending
        queue.enqueue job_run
        waiting_job_run = queue.dequeue
        assert_equal job_run, waiting_job_run

        # now finish it
        queue.finish job_run

        pending_job_runs = queue.list_pending
        assert_empty pending_job_runs
      end
    end
  end

  describe "terminate" do
    it "adds a job_run to the dead queue" do
      clean_slate do
        job_run = job.build_job_run
        job_run.store

        # first move the job_run from waiting to pending
        queue.enqueue job_run
        waiting_job_run = queue.dequeue
        assert_equal job_run, waiting_job_run

        # now terminate it
        queue.terminate job_run

        dead_job_runs = queue.list_dead
        assert_equal [job_run.id], dead_job_runs
      end
    end
  end

end
