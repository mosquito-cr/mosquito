require "../../test_helper"

describe "Mosquito::Runner#enqueue_periodic_job_runs" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job)      { PeriodicTestJob.new }
  getter(runner)        { Mosquito::TestableRunner.new }

  def setup
    Mosquito::Base.register_job_mapping queue.name, PeriodicTestJob
    Mosquito::Base.register_job_interval PeriodicTestJob, interval: 1.second
  end

  it "enqueues a scheduled job_run at the appropriate time" do
    clean_slate do
      setup
      enqueue_time = Time.utc

      Timecop.freeze(enqueue_time) do
        runner.run :enqueue
      end

      queued_job_runs = queue.backend.dump_waiting_q
      assert queued_job_runs.size >= 1

      last_job_run = queued_job_runs.last
      job_run_metadata = queue.backend.retrieve JobRun.config_key(last_job_run)

      assert_equal enqueue_time.to_unix_ms.to_s, job_run_metadata["enqueue_time"]
    end
  end

  it "doesn't enqueue periodic job_runs when disabled" do
    clean_slate do
      setup

      Mosquito.temp_config(run_cron_scheduler: false) do
        runner.run :enqueue
      end

      queued_job_runs = queue.backend.dump_waiting_q
      assert_equal 0, queued_job_runs.size
    end
  end
end
