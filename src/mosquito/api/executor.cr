module Mosquito::Api
  class Executor
    getter :instance_id
    private getter :metadata

    # Creates an executor inspector.
    # The metadata is readonly and can be used to inspect the state of the executor.
    #
    # see #current_job, #current_job_queue
    def initialize(@instance_id : String)
      @metadata = Metadata.new Observability::Executor.metadata_key(@instance_id), readonly: true
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
