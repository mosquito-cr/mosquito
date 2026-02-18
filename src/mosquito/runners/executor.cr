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

    # How long a job config is persisted after success
    property successful_job_ttl : Int32 { Mosquito.configuration.successful_job_ttl }

    # How long a job config is persisted after failure
    property failed_job_ttl : Int32 { Mosquito.configuration.failed_job_ttl }

    # Where work is received from the overseer.
    getter job_pipeline : Channel(Tuple(JobRun, Queue))
    getter! job_run : JobRun
    getter! queue : Queue

    # Used to notify the overseer that this executor is idle.
    getter idle_bell : Channel(Bool)

    getter overseer : Overseer
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

    def initialize(@overseer : Overseer)
      @job_pipeline = overseer.work_handout
      @idle_bell = overseer.idle_notifier
    end

    # :nodoc:
    def runnable_name : String
      "executor.#{object_id}"
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
      return if overseer.state.stopping?

      self.state = State::Working
      @job_run, @queue = dequeue
      log.trace { "Dequeued #{job_run} from #{queue.name}" }
      execute
      log.trace { "Finished #{job_run} from #{queue.name}" }
      self.state = State::Idle

      observer.heartbeat!
    end

    # Runs a job from a Queue.
    #
    # Execution time is measured and logged, and the job is either forgotten
    # or, if it fails, rescheduled.
    def execute
      observer.execute job_run, queue do
        job_run.run
      end

      if job_run.succeeded?
        queue.forget job_run
        job_run.delete in: successful_job_ttl
      else
        if job_run.rescheduleable?
          next_execution = Time.utc + job_run.reschedule_interval
          queue.reschedule job_run, next_execution
        else
          queue.banish job_run
          job_run.delete in: failed_job_ttl
        end
      end
    end
  end
end
