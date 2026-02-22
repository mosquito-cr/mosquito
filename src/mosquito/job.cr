require "./serializers/*"

module Mosquito
  # A Job is a definition for work to be performed.
  # Jobs are pieces of code which run a JobRun.
  #
  # - Jobs prevent double execution of a job for a job_run
  # - Jobs Rescue when a #perform method fails a job_run for any reason
  # - Jobs can be rescheduleable
  abstract class Job
    Log = ::Log.for(self)

    include Mosquito::Serializers::Primitives

    enum State
      Initialization
      Running
      Succeeded
      Failed
      Aborted
      Preempted

      def executed? : Bool
        succeeded? || failed?
      end
    end

    def log(message)
      ::Log.for(self.class).info { message }
    end

    getter state = State::Initialization

    delegate executed?, succeeded?, failed?, aborted?, preempted?, to: state

    # When a job fails and raises an exception, it will be saved into this attribute.
    getter exception : Exception?

    property job_run_id : String?

    # When a job run fails, should it be added to the retry queue?
    # See: #fail(retry: false)
    property should_retry : Bool = true

    # The queue this job is assigned to.
    # By default every job has it's own named queue:
    #
    # - EmailTheUniverseJob.queue = "email_the_universe"
    def self.queue_name : String
      {{ @type.id }}.to_s.underscore
    end

    # Easily override the queue for any job.
    macro queue_name(name)
      def self.queue_name : String
        "{{ name.id }}"
      end
    end

    # The Queue this job uses to store job_runs.
    def self.queue
      if queue_name.blank?
        Queue.new "default"
      else
        Queue.new queue_name
      end
    end

    # Job name is used to differentiate jobs coming off the same queue.
    # By default it is the class name, and this should never need to be changed.
    private def self.job_name : String
      "{{ @type.id }}".underscore
    end

    def run
      begin
        before_hook
      rescue e : JobPreempted
        Log.info(exception: e) { "Before hook preempted, job will not be executed" }
        @state = State::Preempted
        return
      rescue e : Exception
        Log.error(exception: e) { "Before hook raised, job will not be executed" }
        @state = State::Aborted
        return
      end

      @state = State::Running

      perform

      @state = State::Succeeded
    rescue e
      Log.warn(exception: e) do
        "Job failed! Raised #{e.class}: #{e.message}"
      end

      @exception = e
      @state = State::Failed
    ensure
      after_hook
    end

    def before_hook
      # intentionally left blank
    end

    def after_hook
      # intentionally left blank
    end

    def retry_later
      fail
    end

    # To be called from inside a before hook.
    # Preempts this job, preventing execution. The job will be rescheduled.
    def preempt(reason = "")
      raise JobPreempted.new(reason)
    end

    macro before(&block)
      def before_hook
        {% if @type.methods.map(&.name).includes?(:before_hook.id) %}
          previous_def
        {% else %}
          super
        {% end %}

        {{ yield }}
      end
    end

    macro after(&block)
      def after_hook
        {% if @type.methods.map(&.name).includes?(:after_hook.id) %}
          previous_def
        {% else %}
          super
        {% end %}

        {{ yield }}
      end
    end

    # abstract, override in a Job descendant to do something productive
    def perform
      Log.error { "No job definition found for #{self.class.name}" }
      fail
    end

    # To be called from inside a #perform
    # Marks this job as a failure. By default, if the job is a candidate for
    # re-scheduling, it will be run again at a later time.
    def fail(reason = "", *, retry : Bool = true)
      @should_retry = @should_retry && retry

      raise JobFailed.new(reason)
    end

    # abstract, override if desired.
    #
    # True if this job is rescheduleable, false if not.
    def rescheduleable? : Bool
      true
    end

    # abstract, override if desired.
    #
    # For a given retry count, is this job rescheduleable?
    def rescheduleable?(retry_count : Int32) : Bool
      rescheduleable? && retry_count < 5
    end

    # abstract, override if desired.
    #
    # For a given retry count, how long should the delay between
    # job attempts be?
    def reschedule_interval(retry_count : Int32) : Time::Span
      2.seconds * (retry_count ** 2)
      # retry 1 = 2 minutes
      #       2 = 8
      #       3 = 18
      #       4 = 32
    end

    def metadata : Metadata
      @metadata ||= begin
        Metadata.new self.class.metadata_key
      end
    end

    def self.metadata : Metadata
      Metadata.new metadata_key, readonly: true
    end

    def self.metadata_key
      Mosquito.backend.build_key "job_metadata", self.name.underscore
    end
  end
end
