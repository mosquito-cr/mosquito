module Mosquito
  class RedisBackend < Mosquito::Backend
    QUEUES = %w(waiting scheduled pending dead config)

    {% for q in QUEUES %}
      def {{q.id}}_q
        key {{q}}, name
      end
    {% end %}

    def self.store_job_config(job : Mosquito::Job.class) : Nil
      Redis.instance.store_hash job.queue.config_key, job.config
    end

    def self.store(key : String, value : Hash(String, String)) : Nil
      Redis.instance.store_hash key, value
    end

    def self.retrieve(key : String) : Hash(String, String)
      Redis.instance.retrieve_hash key
    end

    def self.delete(key : String, in ttl = 0) : Nil
      if (ttl > 0)
        Redis.instance.expire key, ttl
      else
        Redis.instance.del key
      end
    end

    def self.ttl(key : String) : Int64
      Mosquito::Redis.instance.ttl key
    end

    def self.list_queues : Array(String)
      search_queue_prefixes = QUEUES.first(2)

      search_queue_prefixes.map do |search_queue|
        key = key search_queue, "*"
        long_names = Redis.instance.keys key
        queue_prefix = key(search_queue) + ":"

        long_names.map(&.to_s).map do |long_name|
          long_name.sub(queue_prefix, "")
        end
      end.uniq.flatten
    end

    def self.flush : Nil
      Redis.instance.flushall
    end

    def schedule(task : Task, at scheduled_time : Time)
      Redis.instance.zadd scheduled_q, scheduled_time.to_unix_ms, task.id
    end

    def deschedule : Array(Task)
      time = Time.utc
      overdue_tasks = Redis.instance.zrangebyscore scheduled_q, 0, time.to_unix_ms

      return [] of Task unless overdue_tasks.any?

      overdue_tasks.map do |task_id|
        Redis.instance.zrem scheduled_q, task_id
        Task.retrieve task_id.as(String)
      end.compact
    end

    def enqueue(task : Task)
      Redis.instance.lpush waiting_q, task.id
    end

    def dequeue : Task?
      if id = Redis.instance.rpoplpush waiting_q, pending_q
        Task.retrieve id
      end
    end

    def finish(task : Task)
      Redis.instance.lrem pending_q, 0, task.id
    end

    def terminate(task : Task)
      Redis.instance.lpush dead_q, task.id
    end

    def flush : Nil
      Redis.instance.del(
        waiting_q,
        pending_q,
        scheduled_q,
        dead_q
      )
    end

    def size : Int32
      Redis.instance.llen key(name)
    end
  end
end
