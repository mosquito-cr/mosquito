require "../../spec_helper"

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

  it "updates the backend when a failure happens" do
    failing_job_run.run
    saved_job_run = Mosquito::JobRun.retrieve failing_job_run.id.not_nil!
    assert_equal 1, saved_job_run.not_nil!.retry_count
  end

  it "does not reschedule a job which fails with retry=false" do
    job = FailingJob.new
    job.fail_with_retry = false
    job.run

    refute job.should_retry
  end

  it "retries a job_run whose type has no registered job class" do
    clean_slate do
      job_run = create_job_run "no_such_job"
      job_run.run

      assert job_run.failed?
      assert_equal 1, job_run.retry_count
      assert job_run.rescheduleable?
      assert_includes job_run.error_message.to_s, "no_such_job"
    end
  end

  it "is not rescheduleable when the job failed with retry=false" do
    clean_slate do
      Mosquito::Base.register_job_mapping "no_retry_failing_job", NoRetryFailingJob
      job_run = create_job_run "no_retry_failing_job"
      job_run.run

      assert job_run.failed?
      assert_equal 1, job_run.retry_count
      refute job_run.rescheduleable?
    end
  end

  describe "preempted jobs" do
    it "sets state to preempted and does not execute" do
      job = PreemptingJob.new
      job.run
      assert job.preempted?
      refute job.executed?
    end

    it "uses normal backoff when preempted without an until time" do
      job = PreemptingJob.new
      job.run
      assert_equal 2.seconds, job.reschedule_interval(1)
      assert_equal 8.seconds, job.reschedule_interval(2)
    end

    it "uses the until time for reschedule interval when provided" do
      Timecop.freeze(Time.utc) do
        future = Time.utc + 30.seconds
        job = PreemptingJob.new
        job.preempt_until = future
        job.run

        interval = job.reschedule_interval(1)
        assert_equal 30.seconds, interval
      end
    end

    it "falls back to normal backoff when until time is in the past" do
      Timecop.freeze(Time.utc) do
        past = Time.utc - 5.seconds
        job = PreemptingJob.new
        job.preempt_until = past
        job.run

        assert_equal 2.seconds, job.reschedule_interval(1)
      end
    end

    it "respects rescheduleable? override when preempted" do
      job = NonReschedulablePreemptingJob.new
      job.run
      assert job.preempted?
      refute job.rescheduleable?(0)
    end
  end
end
