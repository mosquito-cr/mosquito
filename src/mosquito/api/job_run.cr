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
        ["id", "type", "enqueue_time", "retry_count"].includes? key
      end
    end

    def to_json
      unless found?
        return {not: :found}.to_json
      end

      {
        id: id,
        type: type,
        enqueue_time: enqueue_time,
        retry_count: retry_count
      }.to_json
    end

    def config : Hash(String, String)
      Mosquito.backend.retrieve config_key
    end

    def config_key
      Mosquito.backend.build_key Mosquito::JobRun::CONFIG_KEY_PREFIX, id
    end

    def type : String
      config["type"]
    end

    def enqueue_time : Time
      Time.unix_ms config["enqueue_time"].to_i64
    end

    def retry_count : Int
      config["retry_count"].to_i
    end
  end
end
