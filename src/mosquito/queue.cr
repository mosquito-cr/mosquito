module Mosquito
  class Queue
    ID_PREFIX = {"mosquito"}

    WAITING = "queue"
    PENDING = "pending"
    SCHEDULED = "scheduled"
    DEAD = "dead"

    def self.redis_key(*parts)
      Redis.key ID_PREFIX, parts
    end

    def redis_key(*parts)
      self.class.redis_key *parts
    end

    def waiting_q
      redis_key WAITING, name
    end

    def pending_q
      redis_key PENDING, name
    end

    def scheduled_q
      redis_key SCHEDULED, name
    end

    def dead_q
      redis_key DEAD, name
    end

    getter name

    def initialize(@name : String)
    end

    def enqueue(task : Task)
      Redis.instance.lpush waiting_q, task.id
    end

    def enqueue(task : Task, in interval : Time::Span)
      enqueue task, at: interval.from_now
    end

    def enqueue(task : Task, at execute_time : Time)
      Redis.instance.zadd scheduled_q, execute_time.epoch_ms, task.id
    end

    def dequeue
      task_id = Redis.instance.rpoplpush waiting_q, pending_q
      return unless task_id
      Task.retrieve task_id
    end

    def reschedule(task : Task, execution_time)
      Redis.instance.lrem pending_q, 0, task.id
      enqueue(task, at: execution_time)
    end

    def dequeue_scheduled : Array(Task)
      time = Time.now
      overdue_tasks = Redis.instance.zrangebyscore scheduled_q, 0, time.epoch_ms

      return [] of Task unless overdue_tasks.any?

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

    def length
      Redis.instance.llen redis_key(name)
    end

    def self.list_queues : Array(String)
      search_queue_prefixes = [WAITING, SCHEDULED]

      search_queue_prefixes.map do |prefix|
        long_names = Redis.instance.keys redis_key(prefix, "*")
        queue_prefix = redis_key(prefix) + ":"

        long_names.map(&.to_s).map do |long_name|
          long_name.sub(queue_prefix, "")
        end
      end.uniq.flatten
    end

    def ==(other : self)
      name == other.name
    end
  end
end
