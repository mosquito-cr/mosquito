module Mosquito
  class Api::Overseer
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


  class Observability::Overseer
    getter metadata : Metadata
    getter instance_id : String

    def self.metadata_key(instance_id : String) : String
      Mosquito::Backend.build_key "overseer", instance_id
    end

    def initialize(overseer : Runners::Overseer)
      @instance_id = overseer.object_id.to_s
      @metadata = Metadata.new self.class.metadata_key(instance_id)
    end

    def heartbeat
      # (Re)registers the overseer with the backend.
      Mosquito.backend.register_overseer self.instance_id

      # Update the metadata with the current time.
      metadata.heartbeat!
    end

    def update_executor_list(executors : Array(Runners::Executor)) : Nil
      metadata["executors"] = executors.map(&.object_id).join(",")
    end
  end
end
