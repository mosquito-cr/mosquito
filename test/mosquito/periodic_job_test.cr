require "../test_helper"

describe Mosquito::PeriodicJob do
  let(:runner) { Mosquito::TestableRunner.new }

  it "correctly renders job_type" do
    assert_equal "periodic_test_job", PeriodicTestJob.job_type
  end

  it "builds a job_run" do
    job = PeriodicTestJob.new
    job_run = job.build_job_run

    assert_instance_of JobRun, job_run
    assert_equal PeriodicTestJob.job_type, job_run.type
  end

  it "is not reschedulable" do
    refute PeriodicTestJob.new.rescheduleable?
  end

  it "registers in job mapping" do
    assert_equal PeriodicTestJob, Base.job_for_type(PeriodicTestJob.job_type)
  end

  it "can be scheduled at a MonthSpan interval" do
    clean_slate do
      clear_logs
      Mosquito::Base.register_job_mapping MonthlyJob.queue.name, MonthlyJob
      Mosquito::Base.register_job_interval MonthlyJob, interval: 1.month

      enqueue_time = Time.utc.to_unix_ms
      runner.run :enqueue
      runner.run :run
      runner.run :fetch_queues
      runner.run :run
      MonthlyJob.queue
      assert_includes logs, "monthly job_run ran"
    end
  end

  it "schedules itself for an interval" do
    clean_slate do
      PeriodicTestJob.run_every 2.minutes
      scheduled_job_run = Base.scheduled_job_runs.first
      assert_equal PeriodicTestJob, scheduled_job_run.class
      assert_equal 2.minutes, scheduled_job_run.interval
    end
  end
end
