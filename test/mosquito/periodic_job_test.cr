require "../test_helper"

describe Mosquito::PeriodicJob do
  let(:runner) { Mosquito::TestableRunner.new }

  it "correctly renders job_type" do
    assert_equal "periodic_test_job", PeriodicTestJob.job_type
  end

  it "builds a task" do
    job = PeriodicTestJob.new
    task = job.build_task

    assert_instance_of Task, task
    assert_equal PeriodicTestJob.job_type, task.type
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
      assert_includes logs, "monthly task ran"
    end
  end

  it "schedules itself for an interval" do
    clean_slate do
      PeriodicTestJob.run_every 2.minutes
      scheduled_task = Base.scheduled_tasks.first
      assert_equal PeriodicTestJob, scheduled_task.class
      assert_equal 2.minutes, scheduled_task.interval
    end
  end
end
