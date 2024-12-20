module Mosquito::Api
  class JobRun
    getter id : String

    def initialize(@id : String)
    end

    def found? : Bool
      config.has_key? "type"
    end

    def runtime_parameters : Hash(String, String)
      config.reject do |key, _|
        ["id", "type", "enqueue_time", "retry_count", "started_at", "finished_at"].includes? key
      end
    end

    private def config : Hash(String, String)
      Mosquito.backend.retrieve config_key
    end

    private def config_key
      Mosquito.backend.build_key Mosquito::JobRun::CONFIG_KEY_PREFIX, id
    end

    # The type of job this job run is for.
    def type : String
      config["type"]
    end

    # A Time object representing the moment this job was enqueued.
    def enqueue_time : Time
      Time.unix_ms config["enqueue_time"].to_i64
    end

    def started_at : Time?
      if time = config["started_at"]?
        Time.unix_ms time.to_i64
      end
    end

    def finished_at : Time?
      if time = config["finished_at"]?
        Time.unix_ms time.to_i64
      end
    end

    # The number of times this job has been retried.
    def retry_count : Int
      config["retry_count"].to_i
    end
  end
end
