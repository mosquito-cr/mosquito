module Mosquito
  class PeriodicJobRun
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span | Time::MonthSpan

    # The last executed timestamp for this periodicjob tracked by the backend.
    def last_executed_at?
      if timestamp = @metadata["last_executed_at"]?
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
      @metadata["last_executed_at"] = time.to_unix.to_s

      case interval_ = interval
      when Time::Span
        @metadata.delete(in: interval_ * 3)
      when Time::MonthSpan
        seconds_in_an_average_month = 2_635_200.seconds
        @metadata.delete(in: seconds_in_an_average_month * interval_.value * 3)
      end
    end

    def initialize(@class, @interval)
      @metadata = Metadata.new(Backend.build_key("periodic_jobs", @class.name))
    end

    # Check the last executed timestamp against the current time,
    # and enqueue the job if it's time to execute.
    def try_to_execute : Bool
      now = Time.utc

      if last_executed_at + interval <= now
        execute

        # Weaknesses:
        # - If something interferes with the job run, it won't be correct that it was executed.
        # - if the worker is backlogged, the start time will be different from the last executed time.
        self.last_executed_at = now
        true
      else
        false
      end
    end

    # Enqueues the job for execution
    def execute
      job = @class.new
      job_run = job.build_job_run
      job_run.store
      @class.queue.enqueue job_run
    end
  end
end
