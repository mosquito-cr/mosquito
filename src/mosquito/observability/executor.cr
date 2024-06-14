require "./concerns/counter"
require "./concerns/publisher"

module Mosquito::Observability
  class Executor
    include Publisher
    include Counter

    getter instance_id : String

    getter! current_job : Mosquito::JobRun?
    getter! current_job_queue : Mosquito::Queue?

    getter duration : Time::Span = 0.seconds
    getter executor : Runners::Executor

    def current_job=(job : Mosquito::JobRun)
      @current_job = job
      @metadata["current_job"] = job.id
    end

    def current_job_queue=(queue : Mosquito::Queue)
      @current_job_queue = queue
      @metadata["current_job_queue"] = queue.name
    end

    # :nodoc:
    #
    # The storage key for an executor.
    def self.metadata_key(id : String) : String
      Mosquito::Backend.build_key "executor", id
    end

    # :nodoc:
    # This is the private API accessor which allows the executor to maintain it's own
    # metadata. 
    def initialize(@executor : Mosquito::Runners::Executor)
      @instance_id = executor.instance_id
      @metadata = Metadata.new self.class.metadata_key(@instance_id)
      @publish_context = PublishContext.new executor.overseer.observer.publish_context, [:executor, executor.instance_id]
    end

    # :nodoc:
    #
    # Update the heartbeat timestamp, and re-set the self destruct timer.
    def heartbeat!
      @metadata["last_heartbeat"] = Time.utc.to_s
      @metadata.delete in: 1.hour
    end

    # :nodoc:
    #
    # Updates the metadata to indicate that a job is being executed.
    def start(job_run : Mosquito::JobRun, from queue : Mosquito::Queue)
      # Update the static metadata, and tracking variables
      self.current_job = job_run
      self.current_job_queue = queue

      # Calculate what the duration _might_ be
      expected_duration = Mosquito.backend.average average_key(job_run.type)

      # Publish an event
      publish({
        event: "starting",
        job_run: job_run.id,
        from_queue: queue.name,
        expected_duration_ms: expected_duration
      })

      # Document the job start as a log message
      executor.log.info { "#{"Starting:".colorize.magenta} #{job_run} from #{queue.name}" }
    end

    def average_key(job_run_type : String) : String
      Mosquito.backend.build_key "job", job_run_type, "duration"
    end

    # :nodoc:
    # Used internally to measure and calculate the average job duration for a job type.
    def measure_duration(job_run_type : String) : Nil
      @duration = Time.measure do
        yield
      end

      average_key = average_key(job_run_type)
      Mosquito.backend.average_push average_key, duration.total_milliseconds.to_i
      Mosquito.backend.delete average_key, in: 30.days
    end

    def finish(success : Bool) : Nil
      # Log the job finish
      if success
        log_success_message
      else
        log_failure_message
      end

      # Publish an event to the observability system
      publish({event: "job-finished", job_run: current_job.id})

      count [@publish_context.context, :success]
      count [:queue, current_job_queue.name, :success]
      count [:job, current_job.type, :success]

      # Updates the metadata to indicate that no job is being excuted.
      @metadata["current_job"] = nil
      @metadata["current_job_queue"] = nil
    end

    def log_success_message
      executor.log.info { "#{"Success:".colorize.green} #{current_job} finished and took #{time_with_units duration.total_seconds}" }
    end

    def log_failure_message
      message = String::Builder.new
      message << "Failure: ".colorize.red
      message << current_job
      message << " failed, taking "
      message << time_with_units duration.total_seconds
      message << " and "

      if current_job
        next_execution = Time.utc + current_job.reschedule_interval

        message << "will run again".colorize.cyan
        message << " in "
        message << current_job.reschedule_interval
        message << " (at "
        message << next_execution
        message << ")"
        executor.log.warn { message.to_s }
      else
        message << "cannot be rescheduled".colorize.yellow
        executor.log.error { message.to_s }
      end
    end

    # :nodoc:
    def time_with_units(seconds : Float64)
      if seconds > 0.1
        "#{(seconds).*(100).trunc./(100)}s".colorize.red
      elsif seconds > 0.001
        "#{(seconds * 1_000).trunc}ms".colorize.yellow
      elsif seconds > 0.000_001
        "#{(seconds * 100_000).trunc}µs".colorize.green
      elsif seconds > 0.000_000_001
        "#{(seconds * 1_000_000_000).trunc}ns".colorize.green
      else
        "no discernible time at all".colorize.green
      end
    end

  end
end
