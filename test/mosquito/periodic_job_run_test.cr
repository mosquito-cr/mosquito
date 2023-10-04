require "../test_helper"

describe Mosquito::PeriodicJobRun do
  getter interval : Time::Span = 2.minutes

  it "tries to execute but fails before the interval has passed" do
    now = Time.utc.at_beginning_of_second
    job_run = PeriodicJobRun.new PeriodicTestJob, interval
    job_run.last_executed_at = now

    Timecop.freeze(now + 1.minute) do
      job_run.try_to_execute
      assert_equal now, job_run.last_executed_at
    end
  end

  it "executes" do
    now = Time.utc.at_beginning_of_second
    job_run = PeriodicJobRun.new PeriodicTestJob, interval
    job_run.last_executed_at = now

    Timecop.freeze(now + interval) do
      job_run.try_to_execute
      assert_equal now + interval, job_run.last_executed_at
    end
  end

  it "checks the metadata store for the last executed timestamp" do
    now = Time.utc.at_beginning_of_second
    clean_slate do
      job_run = PeriodicJobRun.new PeriodicTestJob, interval
      job_run.last_executed_at = now - 1.minute

      Timecop.freeze(now) do
        another_job_run = PeriodicJobRun.new PeriodicTestJob, interval
        refute another_job_run.try_to_execute
      end
    end
  end
end
