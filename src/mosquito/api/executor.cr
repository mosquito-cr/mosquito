module Mosquito
  module Api
    class Executor
      getter :instance_id
      private getter :metadata

      def self.metadata_key(instance_id : String) : String
        Backend.build_key "executor", instance_id
      end

      # Creates an executor inspector.
      # The metadata is readonly and can be used to inspect the state of the executor.
      #
      # see #current_job, #current_job_queue
      def initialize(@instance_id : String)
        @metadata = Metadata.new self.class.metadata_key(@instance_id), readonly: true
      end

      # The current job being executed by the executor.
      #
      # When the executor is idle, this will be `nil`.
      def current_job : String?
        metadata["current_job"]?
      end

      # The queue which housed the current job being executed.
      #
      # When the executor is idle, this will be `nil`.
      def current_job_queue : String?
        metadata["current_job_queue"]?
      end

      # The last heartbeat time, or nil if none exists.
      def heartbeat : Time?
        metadata.heartbeat?
      end
    end
  end

  module Observability
    class Executor
      def initialize(executor : Mosquito::Runners::Executor)
        @metadata = Metadata.new Api::Executor.metadata_key executor.object_id.to_s
      end

      def start(job_run : JobRun, from_queue : Queue)
        @metadata["current_job"] = job_run.id
        @metadata["current_job_queue"] = from_queue.name
      end

      def finish(success : Bool)
        @metadata["current_job"] = nil
        @metadata["current_job_queue"] = nil
      end

      delegate heartbeat!, to: @metadata
    end
  end
end
