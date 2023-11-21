require "../test_helper"

describe Mosquito::QueuedJob do
  getter(runner) { Mosquito::TestableRunner.new }
  getter(name) { "test#{rand(1000)}" }
  getter(job : QueuedTestJob) { QueuedTestJob.new }
  getter(queue : Queue) { QueuedTestJob.queue }

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
