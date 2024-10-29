require "../spec_helper"

describe Mosquito::QueuedJob do
  getter(runner) { Mosquito::TestableRunner.new }
  getter(name) { "test#{rand(1000)}" }
  getter(job : QueuedTestJob) { QueuedTestJob.new }
  getter(queue : Queue) { QueuedTestJob.queue }
  getter(queue_hooked_job : QueueHookedTestJob) { QueueHookedTestJob.new }

  describe "enqueue" do
    it "enqueues" do
      clean_slate do
        job_run = job.enqueue
        enqueued = queue.backend.dump_waiting_q
        assert_equal [job_run.id], enqueued
      end
    end

    it "enqueues with a delay" do
      clean_slate do
        job_run = job.enqueue in: 1.minute
        enqueued = queue.backend.dump_scheduled_q
        assert_equal [job_run.id], enqueued
      end
    end

    it "enqueues with a target time" do
      clean_slate do
        job_run = job.enqueue at: 1.minute.from_now
        enqueued = queue.backend.dump_scheduled_q
        assert_equal [job_run.id], enqueued
      end
    end

    it "fires before_enqueue_hook" do
      clean_slate do
        job_run = queue_hooked_job.enqueue
        assert queue_hooked_job.before_hook_ran
      end
    end

    it "doesnt enqueue if before_enqueue_hook fails" do
      clean_slate do
        queue_hooked_job.fail_before_hook = true
        job_run = queue_hooked_job.enqueue
        waiting_q = queue.backend.dump_waiting_q
        assert_empty waiting_q
      end
    end

    it "fires after_enqueue_hook" do
      clean_slate do
        job_run = queue_hooked_job.enqueue
        assert queue_hooked_job.after_hook_ran
      end
    end

    it "passes the job config to the before_enqueue_hook" do
      clean_slate do
        job_run = queue_hooked_job.enqueue
        assert_equal job_run, queue_hooked_job.passed_job_config
      end
    end

    it "passes the job config to the after_enqueue_hook" do
      clean_slate do
        job_run = queue_hooked_job.enqueue
        assert_equal job_run, queue_hooked_job.passed_job_config
      end
    end
  end

  describe "parameters" do
    it "can be passed in" do
      clear_logs
      EchoJob.new("quack").perform
      assert_logs_match "quack"
    end

    it "can have a boolean false passed as a parameter (and it's not assumed to be a nil)" do
      clear_logs
      JobWithHooks.new(false).perform
      assert_includes logs, "Perform Executed"
    end

    it "can be omitted" do
      clean_slate do
        clear_logs
        job = JobWithNoParams.new.perform
        assert_includes logs, "no param job performed"
      end
    end
  end
end
