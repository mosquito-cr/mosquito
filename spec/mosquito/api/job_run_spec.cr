require "../../spec_helper"

describe Mosquito::Api::JobRun do
  # the job run timestamps are stored as a unix epoch with millis, so nanosecond precision is lost.
  def at_beginning_of_millisecond(time)
    time - (time.nanosecond.nanoseconds) + (time.millisecond.milliseconds)
  end

  getter job : QueuedTestJob { QueuedTestJob.new }
  getter job_run : Mosquito::JobRun { job.build_job_run }
  getter api : Mosquito::Api::JobRun { Mosquito::Api::JobRun.new job_run.id }

  it "can look up a job run" do
    job_run.store
    assert api.found?
  end

  it "can look up a job run that doesn't exist" do
    api = Mosquito::Api::JobRun.new "not_a_real_id"
    refute api.found?
  end

  it "can retrieve the job parameters" do
    job_run = JobWithHooks.new(should_fail: false).build_job_run
    job_run.store
    api = Mosquito::Api::JobRun.new job_run.id
    assert_equal "false", api.runtime_parameters["should_fail"]
  end

  it "can retrieve the job type" do
    job_run.store
    assert_equal job.class.name.underscore, api.type
  end

  it "can retrieve the enqueue time" do
    now = Time.utc
    Timecop.freeze now do
      job_run.store
    end

    expected_time = at_beginning_of_millisecond now
    assert_equal expected_time, api.enqueue_time
  end

  it "can retrieve the retry count" do
    job_run.store
    assert_equal 0, api.retry_count
  end

  it "can retrieve the started at timestamp" do
    now = at_beginning_of_millisecond Time.utc
    job_run = create_job_run
    Timecop.freeze now do
      job_run.run
    end

    api = Mosquito::Api::JobRun.new(job_run.id)
    assert_equal now, api.started_at
  end

  it "can retrieve the finished_at timestamp" do
    now = at_beginning_of_millisecond Time.utc
    job_run = create_job_run
    Timecop.freeze now do
      job_run.run
    end

    api = Mosquito::Api::JobRun.new(job_run.id)
    assert_equal now, api.finished_at
  end
end
