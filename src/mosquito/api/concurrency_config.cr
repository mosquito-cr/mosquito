module Mosquito
  # Provides read/write access to the remotely stored concurrency limits
  # used by `RemoteConfigDequeueAdapter`.
  #
  # Supports both global limits (shared by all overseers) and per-overseer
  # limits for asymmetric hardware configurations.
  #
  # ```crystal
  # config = Mosquito::Api::ConcurrencyConfig.instance
  # config.limits                                  # => global limits
  # config.limits(overseer_id: "gpu-worker-1")     # => per-overseer limits
  # config.update({"queue_a" => 5})                # write global
  # config.update({"queue_a" => 1}, overseer_id: "gpu-worker-1")  # write per-overseer
  # config.clear                                   # remove global limits
  # config.clear(overseer_id: "gpu-worker-1")      # remove per-overseer limits
  # ```
  class Api::ConcurrencyConfig
    def self.instance : self
      new
    end

    # Returns the global concurrency limits stored in the backend.
    def limits : Hash(String, Int32)
      RemoteConfigDequeueAdapter.stored_limits
    end

    # Returns the concurrency limits stored for a specific overseer.
    def limits(overseer_id : String) : Hash(String, Int32)
      RemoteConfigDequeueAdapter.stored_limits(overseer_id)
    end

    # Overwrites the global stored concurrency limits with *new_limits*.
    def update(new_limits : Hash(String, Int32)) : Nil
      RemoteConfigDequeueAdapter.store_limits(new_limits)
    end

    # Overwrites the stored concurrency limits for a specific overseer.
    def update(new_limits : Hash(String, Int32), overseer_id : String) : Nil
      RemoteConfigDequeueAdapter.store_limits(new_limits, overseer_id)
    end

    # Removes all globally stored concurrency limits.
    def clear : Nil
      RemoteConfigDequeueAdapter.clear_limits
    end

    # Removes stored concurrency limits for a specific overseer.
    def clear(overseer_id : String) : Nil
      RemoteConfigDequeueAdapter.clear_limits(overseer_id)
    end
  end
end
