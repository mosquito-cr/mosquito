require "../runners/overseer"

require "./concerns/*"

module Mosquito::Observability
  class Overseer
    include Publisher

    Log = ::Log.for self

    getter metadata : Metadata
    getter instance_id : String
    getter overseer : Runners::Overseer

    def self.metadata_key(instance_id : String) : String
      Mosquito::Backend.build_key "overseer", instance_id
    end

    def initialize(@overseer : Runners::Overseer)
      @instance_id = overseer.instance_id
      @metadata = Metadata.new self.class.metadata_key(instance_id)
      @publish_context = PublishContext.new [:overseer, instance_id]
    end

    def heartbeat
      # (Re)registers the overseer with the backend.
      Mosquito.backend.register_overseer self.instance_id

      # Update the metadata with the current time.
      metadata.heartbeat!
      metadata.delete(in: 1.hour)
    end

    def starting
      Log.info { "Starting #{@overseer.executor_count} executors." }
      heartbeat
      publish({event: "starting"})
    end

    def stopping
      Log.info { "Stopping #{@overseer.executors.size} executors." }
      publish({event: "stopping-work"})
    end

    def stopped
      Log.info { "All executors stopped." }
      Log.info { "Overseer #{instance_id} finished for now." }
      publish({event: "exiting"})
    end

    def coordinating
      # publish({event: "coordinating"})
      yield
      # publish({event: "stopping-coordinating"})
    end

    def executor_died(executor : Runners::Executor) : Nil
      Log.fatal do
        <<-MSG
          Executor #{executor.instance_id} died.
          A new executor will be started.
        MSG
      end

      # TODO publish event
    end

    def will_stop(message : String) : Nil
      Log.fatal { "#{message} Overseer will stop." }
      # TODO publish event
    end

    def update_executor_list : Nil
      metadata["executors"] = @overseer.executors.map(&.instance_id).join(",")
    end
  end
end
