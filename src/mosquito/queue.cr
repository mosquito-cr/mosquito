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
    ID_PREFIX = {"mosquito"}
    QUEUES    = %w(waiting scheduled pending dead config)

    {% for q in QUEUES %}
      def {{q.id}}_q
        redis_key {{q}}, name
      end
    {% end %}

    def self.redis_key(*parts)
      Redis.key ID_PREFIX, parts
    end

    def redis_key(*parts)
      self.class.redis_key *parts
    end

    getter name
    getter? empty : Bool

    def initialize(@name : String)
      @empty = false
    end

    def enqueue(task : Task)
      Mosquito.backend.enqueue name, task
    end

    def enqueue(task : Task, in interval : Time::Span)
      enqueue task, at: interval.from_now
    end

    def enqueue(task : Task, at execute_time : Time)
      Mosquito.backend.schedule name, task, execute_time
    end

    def dequeue : Task?
      return if empty?
      return if rate_limited?
      if task_id = Redis.instance.rpoplpush waiting_q, pending_q
        Task.retrieve task_id
      else
        @empty = true
        nil
      end
    end

    def reschedule(task : Task, execution_time)
      Redis.instance.lrem pending_q, 0, task.id
      enqueue(task, at: execution_time)
    end

    def dequeue_scheduled : Array(Task)
      time = Time.utc
      overdue_tasks = Redis.instance.zrangebyscore scheduled_q, 0, time.to_unix_ms

      return [] of Task unless overdue_tasks.any?

      # TODO should this push tasks back onto pending?
      overdue_tasks.map do |task_id|
        Redis.instance.zrem scheduled_q, task_id
        Task.retrieve task_id.as(String)
      end.compact
    end

    def forget(task : Task)
      Redis.instance.lrem pending_q, 0, task.id
    end

    def banish(task : Task)
      Redis.instance.lrem pending_q, 0, task.id
      Redis.instance.lpush dead_q, task.id
    end

    # TODO does this make sense?
    def length : Int32
      Redis.instance.llen redis_key(name)
    end

    def self.list_queues : Array(String)
      search_queue_prefixes = QUEUES.first(2)

      search_queue_prefixes.map do |prefix|
        long_names = Redis.instance.keys redis_key(prefix, "*")
        queue_prefix = redis_key(prefix) + ":"

        long_names.map(&.to_s).map do |long_name|
          long_name.sub(queue_prefix, "")
        end
      end.uniq.flatten
    end

    def ==(other : self) : Bool
      name == other.name
    end

    def flush
      Redis.instance.del waiting_q, pending_q, scheduled_q, dead_q
    end

    # Determines if a task needs to be throttled and not dequeued
    def rate_limited? : Bool
      # Get the latest config for the queue
      config = get_config

      # Return if throttleing is not needed
      return false if config["limit"] == "0" && config["period"] == "0"

      # If the last time a job was executed was more than now + period.seconds ago, reset executed back to 0
      # This handles executions not in same time frame
      # Which otherwise would cause throttling to kick in once executed == limit even if the executions were hours apart with a 60 sec period
      if Time.utc.to_unix > (Time.unix(config["last_executed"].to_i64) + config["period"].to_i.seconds).to_unix
        config["executed"] = "0"
        Redis.instance.store_hash config_q, config
        return false
      end

      # Throttle the job if the next_batch is in the future
      config["next_batch"].to_i64 > Time.utc.to_unix
    end

    private def get_config : Hash(String, String)
      Redis.instance.retrieve_hash config_q
    end
  end
end
