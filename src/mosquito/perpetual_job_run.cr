module Mosquito
  class PerpetualJobRun
    Log = ::Log.for self

    property class : Mosquito::PerpetualJob.class
    property interval : Time::Span | Time::MonthSpan
    getter metadata : Metadata { Metadata.new(Mosquito.backend.build_key("perpetual_jobs", @class.name)) }
    getter observer : Observability::PerpetualJob { Observability::PerpetualJob.new(self) }

    # The last executed timestamp for this perpetual job tracked by the backend.
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
    # and schedules the metadata for deletion after 3*interval seconds.
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
    # and enqueue the job batch if it's time to execute.
    def try_to_execute : Bool
      now = Time.utc

      if last_executed_at + interval <= now
        execute

        self.last_executed_at = now
        observer.enqueued(at: now)
        true
      else
        observer.skipped
        false
      end
    end

    # Creates a bare instance of the job, calls `next_batch`, and
    # enqueues a job run for each returned instance.
    def execute
      job = @class.new
      batch = job.next_batch

      batch.each do |instance|
        job_run = instance.build_job_run
        job_run.store
        @class.queue.enqueue job_run
      end

      observer.batch_enqueued(batch.size)
    end
  end
end
