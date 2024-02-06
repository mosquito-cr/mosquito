require "./run_at_most"
require "../runnable"

module Mosquito::Runners
  # The executor is the center of work in Mosquito, and it's is the demarcation
  # point between Mosquito framework and application code. Above the Executor
  # is entirely Mosquito, and below it is application code.
  #
  # An Executor is responsible for hydrating Job classes with deserialized
  # parameters and calling `Mosquito::Job#run` on them. It measures the time it
  # takes to run a job and provides detailed log messages about the current
  # status.
  #
  # An executor is a `Mosquito::Runnable` and should be interacted with according to
  # the Runnable API.
  #
  # To build an executor, provide a job input channel and an idle bell channel. These
  # channels can be shared between all available executors.
  #
  # The executor will ring the idle bell when it is ready to accept work and then wait
  # for work to show up on the job pipeline. After the job is finished it will ring the
  # bell again and wait for more work.
  class Executor
    include RunAtMost
    include Runnable
    include Metrics::Shorthand

    Log = ::Log.for self
    getter log : ::Log

    # How long a job config is persisted after success
    property successful_job_ttl : Int32 { Mosquito.configuration.successful_job_ttl }

    # How long a job config is persisted after failure
    property failed_job_ttl : Int32 { Mosquito.configuration.failed_job_ttl }

    # Where work is received from the overseer.
    getter job_pipeline : Channel(Tuple(JobRun, Queue))

    # Used to notify the overseer that this executor is idle.
    getter idle_bell : Channel(Bool)
    getter metadata : Metadata
    getter instance_id : String

    private def state=(state : State)
      # Send a message to the overseer that this executor is idle.
      if state == State::Idle
        spawn { idle_bell.send true }
      end

      super
    end

    def self.metadata_key(id : String) : String
      Mosquito::Backend.build_key "executor", id
    end

    def initialize(@job_pipeline, @idle_bell, overseer_context)
      @log = Log.for(object_id.to_s)
      @instance_id = Random::Secure.hex(8)
      @publish_context = PublishContext.new overseer_context, [:executor, instance_id]
      @metadata = Metadata.new self.class.metadata_key(instance_id)
    end

    # :nodoc:
    def runnable_name : String
      "Executor<#{object_id}>"
    end

    # :nodoc:
    def pre_run : Nil
      # Overseer won't try to dequeue and send any jobs unless it
      # knows that an executor is idle, so the first thing to do
      # is mark this executor as idle. See #state=.
      self.state = State::Idle
    end

    # :nodoc:
    def each_run : Nil
      dequeue = job_pipeline.receive?
      return if dequeue.nil?

      self.state = State::Working
      job_run, queue = dequeue
      log.trace { "Dequeued #{job_run} from #{queue.name}" }
      execute job_run, queue
      log.trace { "Finished #{job_run} from #{queue.name}" }
      self.state = State::Idle

      @metadata.heartbeat!
      @metadata.delete in: 1.hour
    end

    # Runs a job from a Queue.
    #
    # Execution time is measured and logged, and the job is either forgotten
    # or, if it fails, rescheduled.
    def execute(job_run : JobRun, from_queue q : Queue)
      log.info { "#{"Starting:".colorize.magenta} #{job_run} from #{q.name}" }

      metric {
        @metadata["current_job_queue"] = q.name
        @metadata["current_job"] = job_run.id
        publish @publish_context, {
          event: "starting",
          job_run: job_run.id,
          from_queue: q.name,
          expected_duration_ms: job_duration(job_run.type)
        }
      }

      duration = Time.measure do
        job_run.run
      end

      if job_run.succeeded?
        log.info { "#{"Success:".colorize.green} #{job_run} finished and took #{time_with_units duration.total_seconds}" }
        q.forget job_run
        job_run.delete in: successful_job_ttl

        metric {
          publish @publish_context, {event: "job-finished", job_run: job_run.id}
          @metadata["current_job"] = nil

          count [@publish_context.context, :success]
          count [:queue, q.name, :success]
          count [:job, job_run.type, :success]

          record_job_duration job_run.type, duration
        }

      else
        message = String::Builder.new
        message << "Failure: ".colorize.red
        message << job_run
        message << " failed, taking "
        message << time_with_units duration.total_seconds
        message << " and "

        if job_run.rescheduleable?
          next_execution = Time.utc + job_run.reschedule_interval
          q.reschedule job_run, next_execution

          message << "will run again".colorize.cyan
          message << " in "
          message << job_run.reschedule_interval
          message << " (at "
          message << next_execution
          message << ")"
          log.warn { message.to_s }

        else
          q.banish job_run
          job_run.delete in: failed_job_ttl

          message << "cannot be rescheduled".colorize.yellow
          log.error { message.to_s }
        end

        metric {
          publish @publish_context, {event: "job-failed", job_run: job_run.id, reschedulable: job_run.rescheduleable? }
          @metadata["current_job"] = nil

          count [@publish_context.context, :failed]
          count [:queue, q.name, :failed]
          count [:job, job_run.type, :failed]
        }
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
