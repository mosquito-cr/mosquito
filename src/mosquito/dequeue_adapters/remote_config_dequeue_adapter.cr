require "./concurrency_limited_dequeue_adapter"

module Mosquito
  # A dequeue adapter that wraps `ConcurrencyLimitedDequeueAdapter` with
  # remotely configurable concurrency limits stored in the Mosquito backend
  # (e.g. Redis).
  #
  # Limits are refreshed by polling the backend at a configurable interval.
  # When the remote key is absent or empty the adapter falls back to the
  # `defaults` hash provided at construction time.
  #
  # Remote values are **merged on top of** defaults: a queue present only in
  # defaults keeps its value, a queue present only in the remote config is
  # added, and a queue present in both uses the remote value.
  #
  # ## Setting limits remotely
  #
  # Use `Mosquito::Api.set_concurrency_limits` to write new limits:
  #
  # ```crystal
  # Mosquito::Api.set_concurrency_limits({"queue_a" => 2, "queue_b" => 10})
  # ```
  #
  # Or read the current effective limits:
  #
  # ```crystal
  # Mosquito::Api.concurrency_limits
  # # => {"queue_a" => 2, "queue_b" => 10}
  # ```
  #
  # ## Example
  #
  # ```crystal
  # Mosquito.configure do |settings|
  #   settings.dequeue_adapter = Mosquito::RemoteConfigDequeueAdapter.new(
  #     defaults: {"queue_a" => 3, "queue_b" => 5},
  #     refresh_interval: 5.seconds,
  #   )
  # end
  # ```
  #
  # In this configuration the adapter starts with the given defaults. Any
  # limits written to the backend via the API will take effect within
  # `refresh_interval` seconds.
  class RemoteConfigDequeueAdapter < DequeueAdapter
    CONFIG_KEY = "concurrency_limits"

    getter defaults : Hash(String, Int32)
    getter refresh_interval : Time::Span
    getter inner : ConcurrencyLimitedDequeueAdapter

    @last_refresh_at : Time = Time::UNIX_EPOCH
    @last_remote_limits : Hash(String, Int32) = {} of String => Int32

    def initialize(
      @defaults : Hash(String, Int32) = {} of String => Int32,
      @refresh_interval : Time::Span = 5.seconds
    )
      @inner = ConcurrencyLimitedDequeueAdapter.new(defaults.dup)
    end

    def dequeue(queue_list : Runners::QueueList) : WorkUnit?
      maybe_refresh_limits
      inner.dequeue(queue_list)
    end

    def finished_with(job_run : JobRun, queue : Queue) : Nil
      inner.finished_with(job_run, queue)
    end

    # Returns the current effective concurrency limits (defaults merged
    # with any remote overrides).
    def limits : Hash(String, Int32)
      inner.limits
    end

    # Returns the current in-flight count for *queue_name*, delegated to
    # the inner adapter.
    def active_count(queue_name : String) : Int32
      inner.active_count(queue_name)
    end

    # Force an immediate refresh from the backend, ignoring the
    # `refresh_interval` timer.
    def refresh_limits : Nil
      remote = load_remote_limits
      merged = defaults.merge(remote)

      if merged != inner.limits
        inner.limits = merged
      end

      @last_refresh_at = Time.utc
    end

    # ----- Backend storage helpers (class-level) -----

    # Reads the concurrency limits hash currently stored in the backend.
    def self.stored_limits : Hash(String, Int32)
      key = Mosquito.backend.build_key(CONFIG_KEY)
      raw = Mosquito.backend.retrieve(key)
      raw.transform_values(&.to_i32)
    end

    # Writes a concurrency limits hash to the backend so that all running
    # `RemoteConfigDequeueAdapter` instances will pick it up on their next
    # refresh cycle.
    def self.store_limits(limits : Hash(String, Int32)) : Nil
      key = Mosquito.backend.build_key(CONFIG_KEY)
      Mosquito.backend.store(key, limits.transform_values(&.to_s))
    end

    # Removes all remotely stored concurrency limits, causing adapters to
    # fall back to their defaults.
    def self.clear_limits : Nil
      key = Mosquito.backend.build_key(CONFIG_KEY)
      Mosquito.backend.delete(key)
    end

    private def maybe_refresh_limits
      now = Time.utc
      if now - @last_refresh_at >= @refresh_interval
        refresh_limits
      end
    end

    private def load_remote_limits : Hash(String, Int32)
      @last_remote_limits = self.class.stored_limits
    rescue
      # If the backend is unreachable or the data is corrupt, fall back
      # to the last known-good remote limits so previously applied overrides
      # are preserved rather than silently reverting to defaults.
      @last_remote_limits
    end
  end
end
