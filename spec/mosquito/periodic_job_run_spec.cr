require "../spec_helper"

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

  it "does not enqueue a second job run when one is already pending" do
    clean_slate do
      now = Time.utc.at_beginning_of_second
      periodic = PeriodicJobRun.new PeriodicTestJob, interval

      # First execution should enqueue.
      Timecop.freeze(now) do
        periodic.last_executed_at = now - interval
        assert periodic.try_to_execute
      end

      queue = PeriodicTestJob.queue
      first_size = queue.size(include_dead: false)
      assert first_size > 0, "Expected at least one job in the queue"

      # Second execution after another interval should be skipped
      # because the first job run hasn't finished yet.
      Timecop.freeze(now + interval) do
        assert periodic.try_to_execute
      end

      second_size = queue.size(include_dead: false)
      assert_equal first_size, second_size
    end
  end

  it "enqueues again after the pending job run finishes" do
    clean_slate do
      now = Time.utc.at_beginning_of_second
      periodic = PeriodicJobRun.new PeriodicTestJob, interval

      # Enqueue the first job run.
      Timecop.freeze(now) do
        periodic.last_executed_at = now - interval
        periodic.try_to_execute
      end

      # Simulate the job finishing by writing finished_at to the backend.
      pending_id = periodic.metadata["pending_run_id"]?
      refute_nil pending_id
      Mosquito.backend.set(
        Mosquito::JobRun.config_key(pending_id.not_nil!),
        "finished_at",
        Time.utc.to_unix_ms.to_s
      )

      queue = PeriodicTestJob.queue
      size_after_first = queue.size(include_dead: false)

      # Now a new interval passes — should enqueue since the previous one finished.
      Timecop.freeze(now + interval) do
        assert periodic.try_to_execute
      end

      size_after_second = queue.size(include_dead: false)
      assert size_after_second > size_after_first
    end
  end

  it "enqueues again when the pending job run config has been cleaned up" do
    clean_slate do
      now = Time.utc.at_beginning_of_second
      periodic = PeriodicJobRun.new PeriodicTestJob, interval

      # Enqueue the first job run.
      Timecop.freeze(now) do
        periodic.last_executed_at = now - interval
        periodic.try_to_execute
      end

      pending_id = periodic.metadata["pending_run_id"]?
      refute_nil pending_id

      # Simulate the job run config being deleted (e.g. TTL expiry).
      Mosquito.backend.delete Mosquito::JobRun.config_key(pending_id.not_nil!)

      queue = PeriodicTestJob.queue
      size_before = queue.size(include_dead: false)

      # Next interval should enqueue because the old run is gone.
      Timecop.freeze(now + interval) do
        assert periodic.try_to_execute
      end

      size_after = queue.size(include_dead: false)
      assert size_after > size_before
    end
  end
end
