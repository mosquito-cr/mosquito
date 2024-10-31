module Mosquito
  module Api
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

  module Observability
    class Executor
      private getter log : ::Log
      def self.metadata_key(instance_id : String) : String
        Backend.build_key "executor", instance_id
      end

      def initialize(executor : Mosquito::Runners::Executor)
        @metadata = Metadata.new self.class.metadata_key executor.object_id.to_s
        @log = Log.for(executor.runnable_name)
      end

      def execute(job_run : JobRun, from_queue : Queue)
        @metadata["current_job"] = job_run.id
        @metadata["current_job_queue"] = from_queue.name
        log.info { "#{"Starting:".colorize.magenta} #{job_run} from #{from_queue.name}" }

        duration = Time.measure do
          yield
        end

        if job_run.succeeded?
          log_success_message job_run, duration
        else
          log_failure_message job_run, duration
        end

        @metadata["current_job"] = nil
        @metadata["current_job_queue"] = nil
      end

      def log_success_message(job_run : JobRun, duration : Time::Span)
        log.info { "#{"Success:".colorize.green} #{job_run} finished and took #{time_with_units duration}" }
      end

      def log_failure_message(job_run : JobRun, duration : Time::Span)
        message = String::Builder.new
        message << "Failure: ".colorize.red
        message << job_run
        message << " failed, taking "
        message << time_with_units duration
        message << " and "

        if job_run.rescheduleable?
          next_execution = Time.utc + job_run.reschedule_interval
          message << "will run again".colorize.cyan
          message << " in "
          message << job_run.reschedule_interval
          message << " (at "
          message << next_execution
          message << ")"
          log.warn { message.to_s }
        else
          message << "cannot be rescheduled".colorize.yellow
          log.error { message.to_s }
        end
      end

      # :nodoc:
      private def time_with_units(duration : Time::Span)
        seconds = duration.total_seconds
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

      delegate heartbeat!, to: @metadata
    end
  end
end
