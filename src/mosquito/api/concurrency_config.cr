module Mosquito
  # Provides read/write access to the remotely stored concurrency limits
  # used by `RemoteConfigDequeueAdapter`.
  #
  # ```crystal
  # config = Mosquito::Api::ConcurrencyConfig.instance
  # config.limits                          # => {"queue_a" => 3}
  # config.update({"queue_a" => 5})        # overwrites all limits
  # config.clear                           # removes remote limits
  # ```
  class Api::ConcurrencyConfig
    def self.instance : self
      new
    end

    # Returns the concurrency limits currently stored in the backend.
    def limits : Hash(String, Int32)
      RemoteConfigDequeueAdapter.stored_limits
    end

    # Overwrites the stored concurrency limits with *new_limits*.
    def update(new_limits : Hash(String, Int32)) : Nil
      RemoteConfigDequeueAdapter.store_limits(new_limits)
    end

    # Removes all remotely stored concurrency limits.
    def clear : Nil
      RemoteConfigDequeueAdapter.clear_limits
    end
  end
end
