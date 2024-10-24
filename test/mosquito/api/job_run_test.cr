require "../../test_helper"

describe Mosquito::Api::JobRun do
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

    # the enqueue time is stored as a unix epoch with millis, so nanosecond precision is lost.
    expected_time = now - (now.nanosecond.nanoseconds) + (now.millisecond.milliseconds)
    assert_equal expected_time, api.enqueue_time
  end

  it "can retrieve the retry count" do
    job_run.store
    assert_equal 0, api.retry_count
  end
end
