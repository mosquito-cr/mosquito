module Mosquito
  # Wraps a PerpetualJob class with its polling interval and tracks
  # when the last poll occurred.  Used by the PerpetualJobRunner to
  # decide when to call `next_batch` and enqueue the results.
  class PerpetualJobRun
    Log = ::Log.for self

    property class : Mosquito::QueuedJob.class
    property interval : Time::Span
    getter metadata : Metadata { Metadata.new(Mosquito.backend.build_key("perpetual_jobs", @class.name)) }

    def initialize(@class, @interval)
    end

    # The last time this perpetual job was polled, or epoch-zero if never.
    def last_polled_at? : Time?
      if timestamp = metadata["last_polled_at"]?
        Time.unix(timestamp.to_i)
      end
    end

    def last_polled_at : Time
      last_polled_at? || Time.unix(0)
    end

    def last_polled_at=(time : Time)
      metadata["last_polled_at"] = time.to_unix.to_s
      metadata.delete(in: interval * 3)
    end

    # Check whether the polling interval has elapsed and, if so,
    # instantiate a blank job and enqueue whatever `next_batch` returns.
    def try_to_poll : Bool
      now = Time.utc

      if last_polled_at + interval <= now
        poll
        self.last_polled_at = now
        true
      else
        false
      end
    end

    # Create a fresh instance of the job class and call `next_batch`.
    # Each returned job is enqueued via its normal `#enqueue` method.
    def poll
      job = @class.new
      batch = job.next_batch
      return if batch.empty?

      Log.info { "#{@class.name}: next_batch returned #{batch.size} job(s)" }

      batch.each do |next_job|
        if queued = next_job.as?(QueuedJob)
          queued.enqueue
        end
      end
    end
  end
end
