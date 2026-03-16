require "../spec_helper"

describe Mosquito::PerpetualJobRun do
  getter interval : Time::Span = 2.minutes

  it "tries to execute but skips before the interval has passed" do
    now = Time.utc.at_beginning_of_second
    job_run = PerpetualJobRun.new PerpetualTestJob, interval
    job_run.last_executed_at = now

    Timecop.freeze(now + 1.minute) do
      refute job_run.try_to_execute
      assert_equal now, job_run.last_executed_at
    end
  end

  it "executes when the interval has passed" do
    now = Time.utc.at_beginning_of_second
    job_run = PerpetualJobRun.new PerpetualTestJob, interval
    job_run.last_executed_at = now

    PerpetualTestJob.next_batch_items = [] of PerpetualTestJob

    Timecop.freeze(now + interval) do
      assert job_run.try_to_execute
      assert_equal now + interval, job_run.last_executed_at
    end
  end

  it "enqueues a job run for each item in the batch" do
    clean_slate do
      now = Time.utc.at_beginning_of_second
      perpetual = PerpetualJobRun.new PerpetualTestJob, interval

      PerpetualTestJob.next_batch_items = [
        PerpetualTestJob.new(value: "one"),
        PerpetualTestJob.new(value: "two"),
        PerpetualTestJob.new(value: "three"),
      ]

      Timecop.freeze(now) do
        perpetual.last_executed_at = now - interval
        assert perpetual.try_to_execute
      end

      queue = PerpetualTestJob.queue
      assert_equal 3, queue.size(include_dead: false)
    end
  end

  it "enqueues nothing when next_batch returns empty" do
    clean_slate do
      now = Time.utc.at_beginning_of_second
      perpetual = PerpetualJobRun.new PerpetualTestJob, interval

      PerpetualTestJob.next_batch_items = [] of PerpetualTestJob

      Timecop.freeze(now) do
        perpetual.last_executed_at = now - interval
        assert perpetual.try_to_execute
      end

      queue = PerpetualTestJob.queue
      assert_equal 0, queue.size(include_dead: false)
    end
  end

  it "checks the metadata store for the last executed timestamp" do
    now = Time.utc.at_beginning_of_second
    clean_slate do
      job_run = PerpetualJobRun.new PerpetualTestJob, interval
      job_run.last_executed_at = now - 1.minute

      Timecop.freeze(now) do
        another_job_run = PerpetualJobRun.new PerpetualTestJob, interval
        refute another_job_run.try_to_execute
      end
    end
  end
end
