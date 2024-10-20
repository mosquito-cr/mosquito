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

    getter observer : Observability::Executor {
      Observability::Executor.new self
    }

    private def state=(state : State)
      # Send a message to the overseer that this executor is idle.
      if state == State::Idle
        spawn { idle_bell.send true }
      end

      super
    end

    def initialize(@job_pipeline, @idle_bell)
      @log = Log.for(object_id.to_s)
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

      observer.heartbeat!
    end

    # Runs a job from a Queue.
    #
    # Execution time is measured and logged, and the job is either forgotten
    # or, if it fails, rescheduled.
    def execute(job_run : JobRun, from_queue q : Queue)
      log.info { "#{"Starting:".colorize.magenta} #{job_run} from #{q.name}" }

      observer.start job_run, q

      duration = Time.measure do
        job_run.run
      end.total_seconds

      observer.finish job_run.succeeded?

      if job_run.succeeded?
        log.info { "#{"Success:".colorize.green} #{job_run} finished and took #{time_with_units duration}" }
        q.forget job_run
        job_run.delete in: successful_job_ttl

      else
        message = String::Builder.new
        message << "Failure: ".colorize.red
        message << job_run
        message << " failed, taking "
        message << time_with_units duration
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
