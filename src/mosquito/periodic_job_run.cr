module Mosquito
  class PeriodicJobRun
    Log = ::Log.for self

    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span | Time::MonthSpan
    getter metadata : Metadata { Metadata.new(Mosquito.backend.build_key("periodic_jobs", @class.name)) }
    getter observer : Observability::PeriodicJob { Observability::PeriodicJob.new(self) }

    # The last executed timestamp for this periodicjob tracked by the backend.
    def last_executed_at?
      if timestamp = metadata["last_executed_at"]?
        Time.unix(timestamp.to_i)
      else
        nil
      end
    end

    # The last executed timestamp, or "never" if it doesn't exist.
    def last_executed_at
      last_executed_at? || Time.unix(0)
    end

    # Updates the last executed timestamp in the backend,
    # and schedules the metadata for deletion after 3*interval
    # seconds.
    #
    # For Time::Span intervals, the TTL is set to 3 * interval.
    # For Time::MonthSpan intervals, the TTL is set to approximately 3 * interval.
    #
    # A month is approximated to 2635200 seconds, or 30.5 days.
    def last_executed_at=(time : Time)
      metadata["last_executed_at"] = time.to_unix.to_s

      case interval_ = interval
      when Time::Span
        metadata.delete(in: interval_ * 3)
      when Time::MonthSpan
        seconds_in_an_average_month = 2_635_200.seconds
        metadata.delete(in: seconds_in_an_average_month * interval_.value * 3)
      end
    end

    def initialize(@class, @interval)
    end

    # Check the last executed timestamp against the current time,
    # and enqueue the job if it's time to execute.
    def try_to_execute : Bool
      now = Time.utc

      if last_executed_at + interval <= now
        if pending_job_run?
          Log.info { "Skipping enqueue for #{@class.name}: a job run is already pending" }
        else
          execute
        end

        self.last_executed_at = now
        observer.enqueued(at: now)
        true
      else
        observer.skipped
        false
      end
    end

    # Returns true if a previously enqueued job run has not yet finished.
    # This prevents duplicate enqueues when executors are busy and the
    # periodic interval elapses multiple times before the job is run.
    def pending_job_run? : Bool
      if pending_id = metadata["pending_run_id"]?
        if job_run = JobRun.retrieve(pending_id)
          return true if job_run.finished_at.nil?
        end

        # Job run has finished or was cleaned up; clear the stale reference.
        metadata["pending_run_id"] = nil
      end

      false
    end

    # Enqueues the job for execution and records the job run id so that
    # subsequent intervals can detect that a run is already pending.
    def execute
      job = @class.new
      job_run = job.build_job_run
      job_run.store
      @class.queue.enqueue job_run
      metadata["pending_run_id"] = job_run.id
    end
  end
end
