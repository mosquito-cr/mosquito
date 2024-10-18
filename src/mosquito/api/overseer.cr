module Mosquito::Api
  class Overseer
    getter :instance_id
    private getter :metadata

    def initialize(@instance_id : String)
      @metadata = Metadata.new Observability::Overseer.metadata_key(@instance_id), readonly: true
    end

    def self.all : Array(self)
      Mosquito.backend.list_overseers.map do |id|
        new id
      end
    end

    def executors : Array(Executor)
      if executor_list = @metadata["executors"]?
        executor_list.split(",").map do |name|
          Executor.new name
        end
      else
        [] of Executor
      end
    end

    def last_heartbeat : Time?
      metadata.heartbeat?
    end
  end
end
