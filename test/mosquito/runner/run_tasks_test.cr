require "../../test_helper"

describe "Mosquito::Runner#run_next_task" do
  let(:runner) { Mosquito::TestableRunner.new }

  def register_mappings
    Mosquito::Base.register_job_mapping "mosquito::test_jobs::queued", Mosquito::TestJobs::Queued
    Mosquito::Base.register_job_mapping "failing_job", FailingJob
    Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", NonReschedulableFailingJob
  end

  def default_job_config(job)
    Mosquito.backend.store(job.queue.config_key, {
      "limit" => "0",
      "period" => "0",
      "executed" => "0",
      "next_batch" => "0",
      "last_executed" => "0"
    })
  end

  def run_task(job)
    job.reset_performance_counter!

    default_job_config job

    job.new.enqueue

    runner.run :fetch_queues
    runner.run :run
  end

  it "runs a task" do
    vanilla do
      register_mappings

      run_task Mosquito::TestJobs::Queued
      assert_equal 1, Mosquito::TestJobs::Queued.performances
    end
  end

  it "logs a success message" do
    vanilla do
      register_mappings

      clear_logs
      run_task Mosquito::TestJobs::Queued
      assert_includes logs, "Success"
    end
  end

  it "logs a failure message" do
    vanilla do
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
    vanilla do
      register_mappings

      run_task NonReschedulableFailingJob

      runner.run :fetch_queues
      runner.run :run

      assert_includes logs, "cannot be rescheduled"
    end
  end

  it "schedules deletion of a task that hard failed" do
    vanilla do
      register_mappings

      # Manually building and enqueuing the task so we have a
      # local copy of the task to query the backend with.
      # Logic from QueuedJob#enqueue.
      job = NonReschedulableFailingJob.new
      default_job_config NonReschedulableFailingJob
      task = job.build_task
      task.store
      NonReschedulableFailingJob.queue.enqueue task

      runner.run :fetch_queues
      runner.run :run

      ttl = Mosquito.backend.ttl task.config_key
      assert_equal runner.failed_job_ttl, ttl
    end
  end

  it "purges a successful task from the backend" do
    vanilla do
      register_mappings
      clear_logs

      # Manually building and enqueuing the task so we have a
      # local copy of the task to query the backend with.
      # Logic from QueuedJob#enqueue.

      job = Mosquito::TestJobs::Queued.new
      default_job_config Mosquito::TestJobs::Queued
      task = job.build_task
      task.store
      Mosquito::TestJobs::Queued.queue.enqueue task

      runner.run :fetch_queues
      runner.run :run

      assert_includes logs, "Success"

      Mosquito::TestJobs::Queued.queue.enqueue task
      ttl = Mosquito.backend.ttl task.config_key
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
