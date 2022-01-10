require "../../test_helper"

describe "Mosquito::Runner#enqueue_periodic_tasks" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job)      { Mosquito::TestJobs::Periodic.new }
  getter(runner)        { Mosquito::TestableRunner.new }

  def setup
    Mosquito::Base.register_job_mapping queue.name, Mosquito::TestJobs::Periodic
    Mosquito::Base.register_job_interval Mosquito::TestJobs::Periodic, interval: 1.second
  end

  it "enqueues a scheduled task at the appropriate time" do
    clean_slate do
      setup
      enqueue_time = Time.utc

      Timecop.freeze(enqueue_time) do
        runner.run :enqueue
      end

      queued_tasks = queue.backend.dump_waiting_q
      assert queued_tasks.size >= 1

      last_task = queued_tasks.last
      task_metadata = queue.backend.retrieve Task.config_key(last_task)

      assert_equal enqueue_time.to_unix_ms.to_s, task_metadata["enqueue_time"]
    end
  end

  it "doesn't enqueue periodic tasks when disabled" do
    clean_slate do
      setup

      Mosquito.temp_config(run_cron_scheduler: false) do
        runner.run :enqueue
      end

      queued_tasks = queue.backend.dump_waiting_q
      assert_equal 0, queued_tasks.size
    end
  end
end
