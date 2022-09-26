module Mosquito
  # A JobRun is a unit of work which will be performed by a Job.
  # JobRuns know how to:
  # - store and retrieve their data to and from the datastore
  # - figure out what Job class they match to
  # - build an instance of that Job class and pass off the config data
  # - Ask the job to run
  #
  # JobRun data is called `config` and is persisted in the backend under the key
  # `mosquito:job_run:job_run_id`.
  class JobRun
    getter type
    getter enqueue_time : Time
    getter id : String
    getter retry_count = 0
    getter job : Mosquito::Job?

    def job! : Mosquito::Job
      job || raise RuntimeError.new("No job yet retrieved for job_run.")
    end

    # :nodoc:
    property config

    CONFIG_KEY_PREFIX = "job_run"

    # The config key is the backend storage key for the metadata of this job_run.
    def config_key
      self.class.config_key id
    end

    # :ditto:
    def self.config_key(*parts)
      Mosquito.backend.build_key CONFIG_KEY_PREFIX, parts
    end

    def initialize(type : String)
      new type
    end

    def initialize(
      @type : String,
      @enqueue_time : Time = Time.utc,
      id : String? = nil,
      @retry_count : Int32 = 0
    )

      @id = id || KeyBuilder.build @enqueue_time.to_unix_ms.to_s, rand(1000)
      @config = {} of String => String
      @job = nil
    end

    # Stores this job run configuration and metadata in the backend.
    def store
      fields = config.dup
      fields["enqueue_time"] = enqueue_time.to_unix_ms.to_s
      fields["type"] = type
      fields["retry_count"] = retry_count.to_s

      Mosquito.backend.store config_key, fields
    end

    # Deletes this job_run from the backend.
    # Optionally, after a delay in seconds (handled by the backend).
    def delete(in ttl = 0)
      Mosquito.backend.delete config_key, ttl
    end

    # Builds a Job instance from this job_run. Populates the job with config from
    # the backend.
    def build_job : Mosquito::Job
      if job = @job
        return job
      end

      @job = instance = Base.job_for_type(type).new

      if instance.responds_to? :vars_from
        instance.vars_from config
      end

      instance.job_run_id = id
      instance
    end

    # Builds and runs the job with this job_run config.
    def run
      instance = build_job
      instance.run

      if executed? && failed?
        @retry_count += 1
        store
      end
    end

    # Fails this job run and make sure it's persisted as such.
    def fail
      @retry_count += 1
      store
    end

    # For the current retry count, is the job rescheduleable?
    def rescheduleable?
      job!.rescheduleable? @retry_count
    end

    # For the current retry count, how long should a runner wait before retry?
    def reschedule_interval
      job!.reschedule_interval @retry_count
    end

    # :nodoc:
    delegate :executed?, :succeeded?, :failed?, :failed, :rescheduled, to: job!

    # Used to construct a job_run from the parameters stored in the backend.
    def self.retrieve(id : String)
      fields = Mosquito.backend.retrieve config_key(id)

      return unless name = fields.delete "type"
      return unless timestamp = fields.delete "enqueue_time"
      retry_count = (fields.delete("retry_count") || 0).to_i

      instance = new(name, Time.unix_ms(timestamp.to_i64), id, retry_count)
      instance.config = fields

      instance
    end

    # Updates this job_run config from the backend.
    def reload : Nil
      config.merge! Mosquito.backend.retrieve config_key
      @retry_count = config["retry_count"].to_i
    end

    def to_s(io : IO)
      "#{type}<#{id}>".to_s(io)
    end

    def ==(other : self)
      id == self.id
    end
  end
end
