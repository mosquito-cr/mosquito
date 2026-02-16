require "../../spec_helper"

describe "job_run running" do
  # the job run timestamps are stored as a unix epoch with millis, so nanosecond precision is lost.
  def at_beginning_of_millisecond(time)
    time - (time.nanosecond.nanoseconds) + (time.millisecond.milliseconds)
  end

  it "uses the lookup table to build a job" do
    job_instance = create_job_run.build_job
    assert_instance_of JobWithConfig, job_instance
  end

  it "populates the variables of a job" do
    job_instance = create_job_run.build_job

    assert_instance_of JobWithConfig, job_instance
    assert_equal job_run_config, job_instance.as(JobWithConfig).config
  end

  it "runs the job" do
    JobWithPerformanceCounter.reset_performance_counter!
    create_job_run("job_with_performance_counter").run
    assert_equal 1, JobWithPerformanceCounter.performances
  end

  it "sets started_at when a job is run" do
    now = at_beginning_of_millisecond Time.utc
    job_run = create_job_run
    Timecop.freeze now do
      job_run.run
    end
    assert_equal now, job_run.started_at
  end

  it "sets finished_at when a job is run" do
    now = at_beginning_of_millisecond Time.utc
    job_run = create_job_run
    Timecop.freeze now do
      job_run.run
    end
    assert_equal now, job_run.finished_at
  end

  it "has nil timestamps before a job is run" do
    job_run = create_job_run
    assert_nil job_run.started_at
    assert_nil job_run.finished_at
  end
end
