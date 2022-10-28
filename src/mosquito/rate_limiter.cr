module Mosquito::RateLimiter
  module ClassMethods
    # Configures rate limiting for this job.
    #
    # `limit` and `per` are used to control the run count and the window
    # duration. Defaults to a limit of 1 run per second.
    #
    # `increment` is used to indicate how many "hits" against a single job is
    # worth. Defaults to 1.
    #
    # `key` is used to combine rate limiting functions across multiple jobs.
    def throttle(*,
      limit : Int32 = 1,
      per : Time::Span = 1.second,
      increment = 1,
      key = self.name.underscore,
      persist_run_count : Bool = false
    )
      @@rate_limit_ceiling = limit
      @@rate_limit_interval = per
      @@rate_limit_key = Mosquito.backend.build_key "rate_limit", key
      @@rate_limit_increment = increment
      @@persist_run_count = persist_run_count
    end

    # Statistics about the rate limiter, including both the configuration
    # parameters and the run counts.
    def rate_limit_stats : NamedTuple
      meta = metadata

      window_start = if window_start_ = meta["window_start"]?
        Time.unix window_start_.to_i
      else
        Time::UNIX_EPOCH
      end

      run_count = if run_count_ = meta["run_count"]?
        run_count_.to_i
      else
        0
      end

      {
        interval: @@rate_limit_interval,
        key: @@rate_limit_key,
        increment: @@rate_limit_increment,
        limit: @@rate_limit_ceiling,
        window_start: window_start,
        run_count: run_count
      }
    end

    # Provides an instance of the metadata store used to track rate limit
    # stats.
    def metadata : Metadata
      Metadata.new @@rate_limit_key
    end

    # Resolves the key used to index the metadata store for this test.
    def rate_limit_key
      @@rate_limit_key
    end
  end

  macro included
    extend ClassMethods

    @@rate_limit_ceiling = -1
    @@rate_limit_interval : Time::Span = 1.second
    @@rate_limit_key = ""
    @@rate_limit_increment = 1
    @@persist_run_count = false

    before do
      update_window_start
      retry_later if rate_limited?
    end

    after do
      increment_run_count if executed?
      decrement_run_count if @@persist_run_count && succeeded?
    end
  end

  @rl_metadata : Metadata?

  # Storage hash for rate limit data.
  def metadata : Metadata
    @rl_metadata ||= self.class.metadata
  end

  # Should this job be cancelled?
  # If not, update the rate limit metadata.
  def rate_limited? : Bool
    return false if @@rate_limit_ceiling < 0
    return true if maxed_rate_for_window?
    false
  end

  # Has the run count exceeded the ceiling for the current window?
  def maxed_rate_for_window? : Bool
    run_count = metadata["run_count"]?.try &.to_i
    run_count ||= 0
    run_count >= @@rate_limit_ceiling
  end

  # Calculates the start of the rate limit window.
  def window_start : Time?
    if start_time = metadata["window_start"]?.try(&.to_i)
      Time.unix start_time
    end
  end

  # When does the current rate limit window expire?
  # Returns nil if the window is already expired.
  def window_expires_at : Time?
    return nil unless started_window = window_start
    expiration_time = started_window + @@rate_limit_interval

    if expiration_time < Time.utc
      nil
    else
      expiration_time
    end
  end

  # Resets the run count and logs the start of window.
  def update_window_start : Nil
    started_window = window_start || Time::UNIX_EPOCH
    now = Time.utc
    if (now - started_window) > @@rate_limit_interval
      metadata["window_start"] = now.to_unix.to_s
      metadata["run_count"] = "0" unless @@persist_run_count
    end
  end

  # Increments the run counter.
  def increment_run_count : Nil
    metadata.increment "run_count", by: increment_run_count_by
  end

  # Decrements the run counter.
  def decrement_run_count : Nil
    metadata.increment "run_count", by: -increment_run_count_by
  end

  # How much the run counter should be incremented by.
  # Implemented as a dynamic method so that it can easily be calculated by
  # some other metric, eg api calls to a third party library.
  def increment_run_count_by : Int32
    @@rate_limit_increment
  end

  # Configure the reschedule interval so that the task is not run again until it
  # should be allowed through the rate limiter.
  def reschedule_interval(retry_count : Int32) : Time::Span
    if rate_limited? && (window_expiration = window_expires_at)
      next_window =  window_expiration - Time.utc
      log "Rate limited: will run again in #{next_window}"
      next_window
    else
      super
    end
  end

  # Configure the rescheduler to always retry if a job is rate limited.
  def rescheduleable?(retry_count : Int32) : Bool
    if rate_limited?
      true
    else
      super
    end
  end
end
