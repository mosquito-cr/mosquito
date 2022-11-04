require "../../test_helper"

describe "Mosquito::Runner#run_next_job_run" do
  let(:runner) { Mosquito::TestableRunner.new }
  getter backend : Mosquito::Backend { Mosquito.backend.named "test" }

  def register_mappings
    Mosquito::Base.register_job_mapping "queued_test_job", QueuedTestJob
    Mosquito::Base.register_job_mapping "failing_job", FailingJob
    Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", NonReschedulableFailingJob
  end

  def run_job_run(job)
    job.reset_performance_counter!

    job.new.enqueue

    runner.run :fetch_queues
    runner.run :run
  end

  it "runs a job_run" do
    clean_slate do
      register_mappings

      run_job_run QueuedTestJob
      assert_equal 1, QueuedTestJob.performances
    end
  end

  it "reschedules a job that failed" do
    clean_slate do
      register_mappings

      now = Time.utc
      job = FailingJob.new
      job_run = job.build_job_run
      job_run.store
      FailingJob.queue.enqueue job_run

      Timecop.freeze now do
        runner.run :fetch_queues
        runner.run :run
      end

      job_run.reload
      assert_equal 1, job_run.retry_count

      Timecop.freeze now + job.reschedule_interval(1) do
        runner.run :fetch_queues
        runner.run :enqueue
        runner.run :run
      end

      job_run.reload
      assert_equal 2, job_run.retry_count
    end
  end

  it "doesnt reschedule a job that cant be rescheduled" do
    clean_slate do
      register_mappings

      run_job_run NonReschedulableFailingJob

      runner.run :fetch_queues
      runner.run :run

      assert_logs_match "cannot be rescheduled"
    end
  end

  it "schedules deletion of a job_run that hard failed" do
    clean_slate do
      register_mappings

      # Manually building and enqueuing the job_run so we have a
      # local copy of the job_run to query the backend with.
      # Logic from QueuedJob#enqueue.
      job = NonReschedulableFailingJob.new
      job_run = job.build_job_run
      job_run.store
      NonReschedulableFailingJob.queue.enqueue job_run

      runner.run :fetch_queues
      runner.run :run

      ttl = backend.expires_in job_run.config_key
      assert_equal runner.failed_job_ttl, ttl
    end
  end

  it "purges a successful job_run from the backend" do
    clean_slate do
      register_mappings
      clear_logs

      # Manually building and enqueuing the job_run so we have a
      # local copy of the job_run to query the backend with.
      # Logic from QueuedJob#enqueue.

      job = QueuedTestJob.new
      job_run = job.build_job_run
      job_run.store
      QueuedTestJob.queue.enqueue job_run

      runner.run :fetch_queues
      runner.run :run

      assert_logs_match "Success"

      QueuedTestJob.queue.enqueue job_run
      ttl = Mosquito.backend.expires_in job_run.config_key
      assert_equal runner.successful_job_ttl, ttl
    end
  end

  it "measures job_run time correctly" do
    [ 0.05.seconds, 0.5.seconds, 1.second, 2.seconds ].each do |interval|
      elapsed_time = Time.measure do
        runner.run { sleep interval }
      end
      assert_in_delta(interval, elapsed_time.total_seconds, delta: 0.02)
    end
  end
end
