module Mosquito::Inspector
  class Executor
    getter instance_id : String

    def initialize(@instance_id)
      @metadata = Metadata.new Mosquito::Runners::Executor.metadata_key(@instance_id), readonly: true
    end

    def config
      key = Mosquito.backend.build_key "runners", name
      config = Mosquito.backend.retrieve key
    end

    def current_job : String?
      @metadata["current_job"]?
    end

    def current_job_queue : String?
      @metadata["current_job_queue"]?
    end
  end
end
