require "../../test_helper"

describe "job_run rescheduling" do
  @failing_job_run : Mosquito::JobRun?
  getter failing_job_run : Mosquito::JobRun { create_job_run "failing_job" }

  it "calculates reschedule interval correctly" do
    intervals = {
      1 => 2,
      2 => 8,
      3 => 18,
      4 => 32
    }

    intervals.each do |count, delay|
      job_run = Mosquito::JobRun.retrieve(failing_job_run.id.not_nil!).not_nil!
      job_run.run
      assert_equal delay.seconds, job_run.reschedule_interval
    end
  end

  it "prevents rescheduling a job too many times" do
    run_job_run = -> do
      job_run = Mosquito::JobRun.retrieve(failing_job_run.id.not_nil!).not_nil!
      job_run.run
      job_run
    end

    max_reschedules = 4
    max_reschedules.times do
      job_run = run_job_run.call
      assert job_run.rescheduleable?
    end

    job_run = run_job_run.call
    refute job_run.rescheduleable?
  end

  it "counts retries upon failure" do
    assert_equal 0, failing_job_run.retry_count
    failing_job_run.run
    assert_equal 1, failing_job_run.retry_count
  end

  it "updates redis when a failure happens" do
    failing_job_run.run
    saved_job_run = Mosquito::JobRun.retrieve failing_job_run.id.not_nil!
    assert_equal 1, saved_job_run.not_nil!.retry_count
  end
end
