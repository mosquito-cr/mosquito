module Mosquito::Inspector
  class Overseer
    Log = ::Log.for self

    getter metadata : Metadata
    getter instance_id : String

    def self.all : Array(self)
      Mosquito.backend.list_overseers.map do |name|
        new name
      end
    end

    def initialize(@instance_id : String)
      @metadata = Metadata.new Mosquito::Runners::Overseer.metadata_key(@instance_id), readonly: true
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

    def <=>(other)
      name <=> other.name
    end

    def last_heartbeat : Time?
      metadata.heartbeat?
    end
  end
end
