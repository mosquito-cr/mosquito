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
    getter started_at : Time?
    getter finished_at : Time?
    getter overseer_id : String?

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
      @retry_count : Int32 = 0,
      @started_at : Time? = nil,
      @finished_at : Time? = nil
    )

      @id = id || KeyBuilder.build @enqueue_time.to_unix_ms.to_s, rand(1000)
      @config = {} of String => String
      @job = nil
    end

    # Stores this job run configuration and metadata in the backend.
    # Nil-valued fields are deleted from the backend hash.
    def store
      fields = {} of String => String?
      config.each { |k, v| fields[k] = v }
      fields["enqueue_time"] = enqueue_time.to_unix_ms.to_s
      fields["type"] = type
      fields["retry_count"] = retry_count.to_s
      fields["overseer_id"] = @overseer_id

      if started_at_ = @started_at
        fields["started_at"] = started_at_.to_unix_ms.to_s
      end

      if finished_at_ = @finished_at
        fields["finished_at"] = finished_at_.to_unix_ms.to_s
      end

      Mosquito.backend.store config_key, fields
    end

    # Deletes this job_run from the backend.
    # Optionally, after a delay in seconds (handled by the backend).
    def delete(in ttl : Int = 0)
      Mosquito.backend.delete config_key, ttl.to_i64
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

      @started_at = Time.utc
      instance.run
      @finished_at = Time.utc

      if executed? && failed?
        @retry_count += 1
      end
      store
    end

    # :nodoc:
    protected def overseer_id=(id : String?)
      @overseer_id = id
    end

    # Marks this job run as claimed by the given overseer and persists
    # the association to the backend. Used by the pending cleanup to
    # determine whether the owning overseer is still alive.
    def claimed_by(overseer : Runners::Overseer)
      @overseer_id = overseer.observer.instance_id
      Mosquito.backend.set config_key, "overseer_id", @overseer_id.not_nil!
    end

    # Fails this job run and make sure it's persisted as such.
    # Clears the overseer_id since the job is no longer in-flight.
    def fail
      @retry_count += 1
      @overseer_id = nil
      store
    end

    # Treats this job run as a failure: increments the retry count and
    # either reschedules with backoff or banishes to the dead queue.
    def retry_or_banish(queue : Queue) : Nil
      fail
      build_job

      if rescheduleable?
        next_execution = Time.utc + reschedule_interval
        queue.reschedule self, next_execution
      else
        queue.banish self
        delete in: Mosquito.configuration.failed_job_ttl
      end
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
    delegate :executed?, :succeeded?, :failed?, :preempted?, :preempt_reason, :failed, :rescheduled, to: job!

    # Used to construct a job_run from the parameters stored in the backend.
    def self.retrieve(id : String)
      fields = Mosquito.backend.retrieve config_key(id)

      return unless name = fields.delete "type"
      return unless timestamp = fields.delete "enqueue_time"
      retry_count = (fields.delete("retry_count") || 0).to_i
      started_at_raw = fields.delete("started_at")
      finished_at_raw = fields.delete("finished_at")

      started_at = started_at_raw ? Time.unix_ms(started_at_raw.to_i64) : nil
      finished_at = finished_at_raw ? Time.unix_ms(finished_at_raw.to_i64) : nil
      overseer_id = fields.delete("overseer_id")

      instance = new(name, Time.unix_ms(timestamp.to_i64), id, retry_count, started_at, finished_at)
      instance.config = fields
      instance.overseer_id = overseer_id

      instance
    end

    # Updates this job_run config from the backend.
    def reload : Nil
      config.merge! Mosquito.backend.retrieve config_key
      @retry_count = config["retry_count"].to_i
      @overseer_id = config.delete("overseer_id")
    end

    def to_s(io : IO)
      "#{type}<#{id}>".to_s(io)
    end

    def ==(other : self)
      id == self.id
    end
  end
end
