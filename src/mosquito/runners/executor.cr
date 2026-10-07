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
    getter job_pipeline : Channel(WorkUnit)
    getter! work_unit : WorkUnit

    # Used to notify the overseer when this executor is idle.
    # Sends the {JobRun, Queue} tuple that was just finished, or nil
    # when the executor first starts up.
    getter finished_bell : Channel(WorkUnit?)

    getter overseer : Overseer
    getter observer : Observability::Executor {
      Observability::Executor.new self
    }

    getter? decommissioned : Bool = false
    @stop_channel = Channel(Nil).new(1)

    # Marks this executor for graceful shutdown. It will stop after
    # completing its current job (if any). Used by both manual scale-down
    # and the autoscaler.
    def decommission!
      return if @decommissioned
      @decommissioned = true
      @stop_channel.send(nil)
    end

    private def job_run : JobRun
      work_unit.job_run
    end

    private def queue : Queue
      work_unit.queue
    end

    private def state=(state : State)
      # Send a message to the overseer that this executor is idle,
      # including the job that was just finished (if any).
      if state == State::Idle
        spawn { finished_bell.send @work_unit }
      end

      super
    end

    def initialize(@overseer : Overseer)
      @job_pipeline = overseer.work_handout
      @finished_bell = overseer.finished_notifier
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

    def stop(wait_group : WaitGroup = WaitGroup.new(1)) : WaitGroup
      decommission!
      super
    end

    # :nodoc:
    def each_run : Nil
      if @decommissioned
        self.state = State::Stopping
        return
      end

      dequeue : WorkUnit? = nil
      begin
        select
        when dequeue = job_pipeline.receive
        when @stop_channel.receive
          self.state = State::Stopping
          return
        end
      rescue Channel::ClosedError
        return
      end

      return unless dequeue

      self.state = State::Working
      @work_unit = dequeue
      log.trace { "Dequeued #{job_run} from #{queue.name}" }

      begin
        execute
      rescue e
        log.error { "Crashed executing #{job_run}: #{e.inspect}" }
        begin
          job_run.retry_or_banish queue
        rescue
          queue.banish job_run
        end
      end

      log.trace { "Finished #{job_run} from #{queue.name}" }

      if @decommissioned
        self.state = State::Stopping
        return
      end

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
      elsif job_run.preempted?
        queue.forget job_run
        queue.enqueue job_run
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
