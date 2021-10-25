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
  # A task is represented in a queue by its id.
  #
  # A task flows through the queues in this manner:
  #
  #
  # ```text
  #  Time=0: Task does not exist yet, lists are empty
  #
  #    Waiting  Pending  Scheduled    Dead
  #
  #  ---------------------------------
  #  Time=1: Task is enqueued
  #
  #    Waiting  Pending  Scheduled    Dead
  #     Task#1
  #
  #  ---------------------------------
  #  Time=2: Task begins running. Task is moved to pending and executed
  #
  #    Waiting  Pending  Scheduled    Dead
  #              Task#1
  #
  #  ---------------------------------
  #  Time=3: Tasks are Enqueued.
  #
  #    Waiting  Pending  Scheduled    Dead
  #     Task#2   Task#1
  #     Task#3
  #
  #  ---------------------------------
  #  Time=4: Task succeeds, next task begins.
  #
  #    Waiting  Pending  Scheduled    Dead
  #     Task#3   Task#2
  #
  #  ---------------------------------
  #  Time=5: Task fails and is scheduled for later, next task begins.
  #
  #    Waiting  Pending  Scheduled     Dead
  #              Task#3  t=7:Task#2
  #
  #  ---------------------------------
  #  Time=6: Task succeeds. Nothing is executing.
  #
  #    Waiting  Pending  Scheduled     Dead
  #                      t=7:Task#2
  #
  #  ---------------------------------
  #  Time=7: Scheduled task is due and is moved to waiting. Nothing is executing.
  #
  #    Waiting  Pending  Scheduled     Dead
  #     Task#2
  #
  #  ---------------------------------
  #  Time=8: Task begins executing (for the second time).
  #
  #    Waiting  Pending  Scheduled     Dead
  #              Task#2
  #
  #  ---------------------------------
  #  Time=9: Task finished successfully. No more tasks present.
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

    def enqueue(task : Task)
      backend.enqueue task
    end

    def enqueue(task : Task, in interval : Time::Span)
      enqueue task, at: interval.from_now
    end

    def enqueue(task : Task, at execute_time : Time)
      backend.schedule task, execute_time
    end

    def dequeue : Task?
      return if empty?
      # return if rate_limited?

      if task = backend.dequeue
        task
      else
        @empty = true
        nil
      end
    end

    def reschedule(task : Task, execution_time)
      backend.finish task
      enqueue(task, at: execution_time)
    end

    def dequeue_scheduled : Array(Task)
      backend.deschedule
    end

    def forget(task : Task)
      backend.finish task
    end

    def banish(task : Task)
      backend.finish task
      backend.terminate task
    end

    def length : Int32
      backend.size
    end

    def ==(other : self) : Bool
      name == other.name
    end

    def flush
      backend.flush
    end

    def self.default_config
      {
        "limit" => "0",
        "period" => "0",
        "executed" => "0",
        "next_batch" => "0",
        "last_executed" => "0"
      }
    end

    def get_config : Hash(String, String)
      self.class.default_config.merge Mosquito.backend.retrieve config_key
    end

    def set_config(config : Hash(String, String))
      Mosquito.backend.store config_key, config
    end

    # Determines if a task needs to be throttled and not dequeued
    # def rate_limited? : Bool
    #   # Get the latest config for the queue
    #   config = get_config

    #   # Return if throttleing is not needed
    #   return false if config["limit"] == "0" && config["period"] == "0"

    #   # If the last time a job was executed was more than now + period.seconds ago, reset executed back to 0
    #   # This handles executions not in same time frame
    #   # Which otherwise would cause throttling to kick in once executed == limit even if the executions were hours apart with a 60 sec period
    #   if Time.utc.to_unix > (Time.unix(config["last_executed"].to_i64) + config["period"].to_i.seconds).to_unix
    #     config["executed"] = "0"
    #     set_config config
    #     return false
    #   end

    #   # Throttle the job if the next_batch is in the future
    #   config["next_batch"].to_i64 > Time.utc.to_unix
    # end
  end
end
