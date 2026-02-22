module Mosquito
  # An interface for inspecting the state of Mosquito Overseers.
  #
  # For more information about overseers, see `Mosquito::Runners::Overseer`.
  class Api::Overseer
    # The instance ID of the overseer being inspected.
    getter :instance_id
    private getter :metadata

    # Creates a new Api::Overseer by its instance ID.
    def initialize(@instance_id : String)
      @metadata = Metadata.new Observability::Overseer.metadata_key(@instance_id), readonly: true
    end

    # Retrieves a list of all overseers in the backend.
    def self.all : Array(self)
      Mosquito.backend.list_overseers.map do |id|
        new id
      end
    end

    # Retrieves a list of executors managed by this overseer.
    def executors : Array(Executor)
      if executor_list = @metadata["executors"]?
        executor_list.split(",").map do |name|
          Executor.new name
        end
      else
        [] of Executor
      end
    end

    # The time the overseer last sent a heartbeat.
    def last_heartbeat : Time?
      metadata.heartbeat?
    end
  end


  class Observability::Overseer
    include Publisher

    getter metadata : Metadata
    getter instance_id : String
    private getter overseer : Runners::Overseer
    private getter log : ::Log

    def self.metadata_key(instance_id : String) : String
      Mosquito::Backend.build_key "overseer", instance_id
    end

    def initialize(@overseer : Runners::Overseer)
      @instance_id = overseer.object_id.to_s
      @log = Log.for(overseer.runnable_name)
      @metadata = Metadata.new self.class.metadata_key(instance_id)
      @publish_context = PublishContext.new [:overseer, overseer.object_id]
    end

    def starting
      log.info { "Starting #{overseer.executor_count} executors." }

      publish({event: "started"})
      heartbeat
    end

    def shutting_down
      log.info { "Shutting down." }
    end

    def stopping
      log.info { "Stopping executors." }
      publish({event: "stopped"})
    end

    def stopped
      log.info { "All executors stopped." }
      log.info { "Finished for now." }
      publish({event: "exited"})

      Mosquito.backend.deregister_overseer self.instance_id
      metadata.delete
    end

    def heartbeat
      # Registration must always happen so that the pending job cleanup
      # mechanism can determine which overseers are still alive.
      Mosquito.backend.register_overseer self.instance_id

      metrics do
        metadata.heartbeat!
      end
    end

    def executor_created(executor : Runners::Executor) : Nil
      publish({event: "executor-created", executor: executor.object_id})
    end

    def executor_died(executor : Runners::Executor) : Nil
      publish({event: "executor-died", executor: executor.object_id})

      log.fatal do
       <<-MSG
          Executor #{executor.runnable_name} died.
          A new executor will be started.
        MSG
      end
    end

    def channels_closed
      log.fatal { "Executor communication channels closed, overseer will stop." }
    end

    def waiting_for_queue_list
      log.debug { "Waited for the queue list to fetch possible queues." }
    end

    def queue_list_died
      log.fatal { "QueueList has died, overseer will stop." }
    end

    def recovered_orphaned_job(job_run : JobRun, overseer_id : String)
      log.warn { "Recovered orphaned job #{job_run.id} from dead overseer #{overseer_id}." }
    end

    def orphaned_jobs_recovered(total : Int32)
      log.warn { "Recovered #{total} orphaned job(s) from pending queues." }
    end

    def recovered_job_from_executor(job_run : JobRun, executor : Runners::Executor)
      log.warn { "Recovered job #{job_run.id} from dead executor #{executor.runnable_name}." }
    end

    def update_executor_list(executors : Array(Runners::Executor)) : Nil
      metrics do
        metadata["executors"] = executors.map(&.object_id).join(",")
      end
    end
  end
end
