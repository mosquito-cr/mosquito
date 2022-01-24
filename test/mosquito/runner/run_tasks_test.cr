require "../../test_helper"

describe "Mosquito::Runner#run_next_task" do
  let(:runner) { Mosquito::TestableRunner.new }
  getter backend : Mosquito::Backend { Mosquito.backend.named "test" }

  def register_mappings
    Mosquito::Base.register_job_mapping "queued_test_job", QueuedTestJob
    Mosquito::Base.register_job_mapping "failing_job", FailingJob
    Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", NonReschedulableFailingJob
  end

  def run_task(job)
    job.reset_performance_counter!

    job.new.enqueue

    runner.run :fetch_queues
    runner.run :run
  end

  it "runs a task" do
    clean_slate do
      register_mappings

      run_task QueuedTestJob
      assert_equal 1, QueuedTestJob.performances
    end
  end

  it "logs a success message" do
    clean_slate do
      register_mappings

      clear_logs
      run_task QueuedTestJob
      assert_includes logs, "Success"
    end
  end

  it "logs a failure message" do
    clean_slate do
      register_mappings
      clear_logs
      run_task FailingJob
      assert_includes logs, "Failure"
    end
  end

  it "reschedules a job that failed" do
    skip
  end

  it "doesnt reschedule a job that cant be rescheduled" do
    clean_slate do
      register_mappings

      run_task NonReschedulableFailingJob

      runner.run :fetch_queues
      runner.run :run

      assert_includes logs, "cannot be rescheduled"
    end
  end

  it "schedules deletion of a task that hard failed" do
    clean_slate do
      register_mappings

      # Manually building and enqueuing the task so we have a
      # local copy of the task to query the backend with.
      # Logic from QueuedJob#enqueue.
      job = NonReschedulableFailingJob.new
      task = job.build_task
      task.store
      NonReschedulableFailingJob.queue.enqueue task

      runner.run :fetch_queues
      runner.run :run

      ttl = backend.expires_in task.config_key
      assert_equal runner.failed_job_ttl, ttl
    end
  end

  it "purges a successful task from the backend" do
    clean_slate do
      register_mappings
      clear_logs

      # Manually building and enqueuing the task so we have a
      # local copy of the task to query the backend with.
      # Logic from QueuedJob#enqueue.

      job = QueuedTestJob.new
      task = job.build_task
      task.store
      QueuedTestJob.queue.enqueue task

      runner.run :fetch_queues
      runner.run :run

      assert_includes logs, "Success"

      QueuedTestJob.queue.enqueue task
      ttl = Mosquito.backend.expires_in task.config_key
      assert_equal runner.successful_job_ttl, ttl

    end
  end

  it "measures task time correctly" do
    [ 0.05.seconds, 0.5.seconds, 1.second, 2.seconds ].each do |interval|
      elapsed_time = Time.measure do
        runner.run { sleep interval }
      end
      assert_in_delta(interval, elapsed_time.total_seconds, delta: 0.02)
    end
  end
end
