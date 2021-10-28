module Mosquito
  class RedisBackend < Mosquito::Backend
    QUEUES = %w(waiting scheduled pending dead)

    {% for q in QUEUES %}
      def {{q.id}}_q
        build_key {{q}}, name
      end
    {% end %}

    def self.store(key : String, value : Hash(String, String)) : Nil
      Mosquito::Redis.instance.hset key, value
    end

    def self.retrieve(key : String) : Hash(String, String)
      Mosquito::Redis.instance.hgetall key
    end

    def self.delete(key : String, in ttl = 0) : Nil
      if (ttl > 0)
        Mosquito::Redis.instance.expire key, ttl
      else
        Mosquito::Redis.instance.del key
      end
    end

    @[Deprecated]
    def self.ttl(key : String) : Int64
      Mosquito::Redis.instance.ttl key
    end

    def self.list_queues : Array(String)
      search_queue_prefixes = QUEUES.first(2)

      search_queue_prefixes.map do |search_queue|
        key = build_key search_queue, "*"
        long_names = Mosquito::Redis.instance.keys key
        queue_prefix = build_key(search_queue) + ":"

        long_names.map(&.to_s).map do |long_name|
          long_name.sub(queue_prefix, "")
        end
      end.uniq.flatten
    end

    # is this even a good idea?
    def self.flush : Nil
      Mosquito::Redis.instance.flushall
    end

    def schedule(task : Task, at scheduled_time : Time)
      Mosquito::Redis.instance.zadd scheduled_q, scheduled_time.to_unix_ms, task.id
    end

    def deschedule : Array(Task)
      time = Time.utc
      overdue_tasks = Mosquito::Redis.instance.zrangebyscore scheduled_q, 0, time.to_unix_ms

      return [] of Task unless overdue_tasks.any?

      overdue_tasks.compact_map do |task_id|
        Mosquito::Redis.instance.zrem scheduled_q, task_id
        Task.retrieve task_id.as(String)
      end
    end

    def enqueue(task : Task)
      Mosquito::Redis.instance.lpush waiting_q, task.id
    end

    def dequeue : Task?
      if id = Mosquito::Redis.instance.rpoplpush waiting_q, pending_q
        Task.retrieve id
      end
    end

    def finish(task : Task)
      Mosquito::Redis.instance.lrem pending_q, 0, task.id
    end

    def terminate(task : Task)
      Mosquito::Redis.instance.lpush dead_q, task.id
    end

    def flush : Nil
      Mosquito::Redis.instance.del(
        waiting_q,
        pending_q,
        scheduled_q,
        dead_q
      )
    end

    def size : Int32
      Mosquito::Redis.instance.llen build_key(name)
    end
  end
end
