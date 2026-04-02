module Mosquito
  # Provides read/write access to the remotely stored executor count
  # used by overseers configured with a stable `overseer_id`.
  #
  # Supports both global counts (shared by all overseers) and per-overseer
  # counts for asymmetric hardware configurations.
  #
  # ```crystal
  # config = Mosquito::Api::ExecutorConfig.instance
  # config.executor_count                                  # => global count or nil
  # config.executor_count(overseer_id: "gpu-worker-1")     # => per-overseer count or nil
  # config.update(8)                                       # write global
  # config.update(2, overseer_id: "gpu-worker-1")          # write per-overseer
  # config.clear                                           # remove global override
  # config.clear(overseer_id: "gpu-worker-1")              # remove per-overseer override
  # ```
  class Api::ExecutorConfig
    CONFIG_KEY = "executor_count"

    def self.instance : self
      new
    end

    # Returns the global executor count stored in the backend, or nil if
    # no override has been set.
    def executor_count : Int32?
      self.class.stored_executor_count
    end

    # Returns the executor count for a specific overseer, or nil if no
    # override has been set for that overseer.
    def executor_count(overseer_id : String) : Int32?
      self.class.stored_executor_count(overseer_id)
    end

    # Writes a global executor count override.
    def update(count : Int32) : Nil
      self.class.store_executor_count(count)
    end

    # Writes an executor count override for a specific overseer.
    def update(count : Int32, overseer_id : String) : Nil
      self.class.store_executor_count(count, overseer_id)
    end

    # Removes the global executor count override.
    def clear : Nil
      self.class.clear_executor_count
    end

    # Removes the executor count override for a specific overseer.
    def clear(overseer_id : String) : Nil
      self.class.clear_executor_count(overseer_id)
    end

    # ----- Backend storage helpers -----

    def self.stored_executor_count : Int32?
      value = Mosquito.backend.get(global_config_key, "count")
      value.try(&.to_i32)
    end

    def self.stored_executor_count(overseer_id : String) : Int32?
      value = Mosquito.backend.get(overseer_config_key(overseer_id), "count")
      value.try(&.to_i32)
    end

    def self.store_executor_count(count : Int32) : Nil
      Mosquito.backend.set(global_config_key, "count", count.to_s)
    end

    def self.store_executor_count(count : Int32, overseer_id : String) : Nil
      Mosquito.backend.set(overseer_config_key(overseer_id), "count", count.to_s)
    end

    def self.clear_executor_count : Nil
      Mosquito.backend.delete(global_config_key)
    end

    def self.clear_executor_count(overseer_id : String) : Nil
      Mosquito.backend.delete(overseer_config_key(overseer_id))
    end

    # Resolves the effective executor count for an overseer by checking
    # per-overseer first, then global. Returns nil if neither is set.
    def self.resolve(overseer_id : String? = nil) : Int32?
      if oid = overseer_id
        stored_executor_count(oid) || stored_executor_count
      else
        stored_executor_count
      end
    end

    protected def self.global_config_key : String
      Mosquito.backend.build_key(CONFIG_KEY)
    end

    protected def self.overseer_config_key(overseer_id : String) : String
      Mosquito.backend.build_key(CONFIG_KEY, overseer_id)
    end
  end
end
