module Mosquito::Api
  # Represents a job run in Mosquito.
  #
  # This class is used to inspect a job run stored in the backend.
  #
  # For more information about a JobRun, see `Mosquito::JobRun`.
  class JobRun
    # The id of the job run.
    getter id : String

    def initialize(@id : String)
    end

    # Does a JobRun with this ID exist in the backend?
    def found? : Bool
      config.has_key? "type"
    end

    # Get the parameters the job was enqueued with.
    def runtime_parameters : Hash(String, String)
      config.reject do |key, _|
        ["id", "type", "enqueue_time", "retry_count", "started_at", "finished_at"].includes? key
      end
    end

    private getter metadata : Metadata {
      Metadata.new(
        Mosquito.backend.build_key(Mosquito::JobRun::CONFIG_KEY_PREFIX, id),
        readonly: true
      )
    }

    private def config : Hash(String, String)
      metadata.to_h
    end

    # The type of job this job run is for.
    def type : String
      config["type"]
    end

    # The moment this job was enqueued.
    def enqueue_time : Time
      Time.unix_ms config["enqueue_time"].to_i64
    end

    # The moment this job was started.
    def started_at : Time?
      if time = config["started_at"]?
        Time.unix_ms time.to_i64
      end
    end

    # The moment this job was finished.
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
