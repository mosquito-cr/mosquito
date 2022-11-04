require "../test_helper"

describe Mosquito::PeriodicJobRun do
  getter interval : Time::Span = 2.minutes

  it "tries to execute but fails before the interval has passed" do
    now = Time.utc
    job_run = PeriodicJobRun.new PeriodicTestJob, interval
    job_run.last_executed_at = now

    Timecop.freeze(now + 1.minute) do
      job_run.try_to_execute
      assert_equal now, job_run.last_executed_at
    end
  end

  it "executes" do
    now = Time.utc
    job_run = PeriodicJobRun.new PeriodicTestJob, interval
    job_run.last_executed_at = now

    Timecop.freeze(now + interval) do
      job_run.try_to_execute
      assert_equal now + interval, job_run.last_executed_at
    end
  end
end
