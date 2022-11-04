module Mosquito
  # A named Queue.
  #
  # Named Queues exist and have 4 ordered lists: waiting, pending, scheduled, and dead.
  #
  # - The Waiting list is for jobs which need to be executed as soon as possible.
  # - The Pending list is for jobs which are currently being executed.
  # - The Scheduled list is indexed by execution time and holds jobs which need to be executed at a later time.
  # - The Dead list is for jobs which have been retried too many times and are no longer viable.
  #
  # A job_run is represented in a queue by its id.
  #
  # A job_run flows through the queues in this manner:
  #
  #
  # ```text
  #  Time=0: JobRun does not exist yet, lists are empty
  #
  #    Waiting  Pending  Scheduled    Dead
  #
  #  ---------------------------------
  #  Time=1: JobRun is enqueued
  #
  #    Waiting  Pending  Scheduled    Dead
  #     JobRun#1
  #
  #  ---------------------------------
  #  Time=2: JobRun begins. JobRun is moved to pending and executed
  #
  #    Waiting  Pending  Scheduled    Dead
  #              JobRun#1
  #
  #  ---------------------------------
  #  Time=3: JobRuns are Enqueued.
  #
  #    Waiting  Pending  Scheduled    Dead
  #     JobRun#2   JobRun#1
  #     JobRun#3
  #
  #  ---------------------------------
  #  Time=4: JobRun succeeds, next job_run begins.
  #
  #    Waiting  Pending  Scheduled    Dead
  #     JobRun#3   JobRun#2
  #
  #  ---------------------------------
  #  Time=5: JobRun fails and is scheduled for later, next job_run begins.
  #
  #    Waiting  Pending  Scheduled     Dead
  #              JobRun#3  t=7:JobRun#2
  #
  #  ---------------------------------
  #  Time=6: JobRun succeeds. Nothing is executing.
  #
  #    Waiting  Pending  Scheduled     Dead
  #                      t=7:JobRun#2
  #
  #  ---------------------------------
  #  Time=7: Scheduled job_run is due and is moved to waiting. Nothing is executing.
  #
  #    Waiting  Pending  Scheduled     Dead
  #     JobRun#2
  #
  #  ---------------------------------
  #  Time=8: JobRun begins executing (for the second time).
  #
  #    Waiting  Pending  Scheduled     Dead
  #              JobRun#2
  #
  #  ---------------------------------
  #  Time=9: JobRun finished successfully. No more job_runs present.
  #
  #    Waiting  Pending  Scheduled     Dead
  #
  # ```
  #
  class Queue
    getter name, config_key
    getter? empty : Bool
    property backend : Mosquito::Backend

    def initialize(@name : String)
      @empty = false
      @backend = Mosquito.backend.named name
      @config_key = @name
    end

    def enqueue(job_run : JobRun) : JobRun
      backend.enqueue job_run
    end

    def enqueue(job_run : JobRun, in interval : Time::Span) : JobRun
      enqueue job_run, at: interval.from_now
    end

    def enqueue(job_run : JobRun, at execute_time : Time) : JobRun
      backend.schedule job_run, execute_time
    end

    def dequeue : JobRun?
      return if empty?

      if job_run = backend.dequeue
        job_run
      else
        @empty = true
        nil
      end
    end

    def reschedule(job_run : JobRun, execution_time)
      backend.finish job_run
      enqueue(job_run, at: execution_time)
    end

    def dequeue_scheduled : Array(JobRun)
      backend.deschedule
    end

    def forget(job_run : JobRun)
      backend.finish job_run
    end

    def banish(job_run : JobRun)
      backend.finish job_run
      backend.terminate job_run
    end

    def size : Int64
      backend.size
    end

    @[Deprecated("see #size")]
    def length : Int64
      backend.size
    end

    def ==(other : self) : Bool
      name == other.name
    end

    def flush
      backend.flush
    end
  end
end
