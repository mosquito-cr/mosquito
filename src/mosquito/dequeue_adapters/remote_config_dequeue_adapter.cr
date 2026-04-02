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
  # ## Per-overseer configuration
  #
  # When `overseer_id` is set, the adapter reads from both the global key
  # and a per-overseer key. The merge order is:
  #
  #   defaults → global remote → per-overseer remote
  #
  # This lets you run overseers on asymmetric hardware and tune each one
  # independently while still sharing a common baseline.
  #
  # ## Setting limits remotely
  #
  # Use `Mosquito::Api.set_concurrency_limits` to write global limits:
  #
  # ```crystal
  # Mosquito::Api.set_concurrency_limits({"queue_a" => 2, "queue_b" => 10})
  # ```
  #
  # Or target a specific overseer:
  #
  # ```crystal
  # Mosquito::Api.set_concurrency_limits({"queue_a" => 1}, overseer_id: "gpu-worker-1")
  # ```
  #
  # ## Example
  #
  # ```crystal
  # Mosquito.configure do |settings|
  #   settings.dequeue_adapter = Mosquito::RemoteConfigDequeueAdapter.new(
  #     defaults: {"queue_a" => 3, "queue_b" => 5},
  #     overseer_id: "gpu-worker-1",
  #     refresh_interval: 5.seconds,
  #   )
  # end
  # ```
  #
  # In this configuration the adapter starts with the given defaults. Any
  # limits written to the backend via the API will take effect within
  # `refresh_interval` seconds. Per-overseer limits override global limits
  # which override defaults.
  class RemoteConfigDequeueAdapter < DequeueAdapter
    CONFIG_KEY = "concurrency_limits"

    getter defaults : Hash(String, Int32)
    getter refresh_interval : Time::Span
    getter inner : ConcurrencyLimitedDequeueAdapter
    getter overseer_id : String?

    @last_refresh_at : Time = Time::UNIX_EPOCH
    @last_remote_limits : Hash(String, Int32) = {} of String => Int32

    def initialize(
      @defaults : Hash(String, Int32) = {} of String => Int32,
      @overseer_id : String? = nil,
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

    # Reads the global concurrency limits hash stored in the backend.
    def self.stored_limits : Hash(String, Int32)
      raw = Mosquito.backend.retrieve(global_config_key)
      raw.transform_values(&.to_i32)
    end

    # Reads the concurrency limits for a specific overseer.
    def self.stored_limits(overseer_id : String) : Hash(String, Int32)
      raw = Mosquito.backend.retrieve(overseer_config_key(overseer_id))
      raw.transform_values(&.to_i32)
    end

    # Overwrites the global concurrency limits with *limits*. Any previously
    # stored queue entries not present in *limits* are removed.
    def self.store_limits(limits : Hash(String, Int32)) : Nil
      key = global_config_key
      Mosquito.backend.delete(key)
      Mosquito.backend.store(key, limits.transform_values(&.to_s)) unless limits.empty?
    end

    # Overwrites the concurrency limits for a specific overseer with *limits*.
    def self.store_limits(limits : Hash(String, Int32), overseer_id : String) : Nil
      key = overseer_config_key(overseer_id)
      Mosquito.backend.delete(key)
      Mosquito.backend.store(key, limits.transform_values(&.to_s)) unless limits.empty?
    end

    # Removes all globally stored concurrency limits, causing adapters to
    # fall back to their defaults (or per-overseer limits if set).
    def self.clear_limits : Nil
      Mosquito.backend.delete(global_config_key)
    end

    # Removes stored concurrency limits for a specific overseer.
    def self.clear_limits(overseer_id : String) : Nil
      Mosquito.backend.delete(overseer_config_key(overseer_id))
    end

    protected def self.global_config_key : String
      Mosquito.backend.build_key(CONFIG_KEY)
    end

    protected def self.overseer_config_key(overseer_id : String) : String
      Mosquito.backend.build_key(CONFIG_KEY, overseer_id)
    end

    private def maybe_refresh_limits
      now = Time.utc
      if now - @last_refresh_at >= @refresh_interval
        refresh_limits
      end
    end

    private def load_remote_limits : Hash(String, Int32)
      global = self.class.stored_limits

      result = if oid = overseer_id
        per_overseer = self.class.stored_limits(oid)
        global.merge(per_overseer)
      else
        global
      end

      @last_remote_limits = result
    rescue
      # If the backend is unreachable or the data is corrupt, fall back
      # to the last known-good remote limits so previously applied overrides
      # are preserved rather than silently reverting to defaults.
      @last_remote_limits
    end
  end
end
