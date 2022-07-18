require "redis"

module Mosquito
  class RedisBackend < Mosquito::Backend
    QUEUES = %w(waiting scheduled pending dead)

    @[AlwaysInline]
    def self.redis
      @@connection ||= ::Redis::PooledClient.new url: Mosquito.configuration.redis_url
    end

    @[AlwaysInline]
    def redis
      self.class.redis
    end

    {% for q in QUEUES %}
      def {{q.id}}_q
        build_key {{q}}, name
      end
    {% end %}

    def self.store(key : String, value : Hash(String, String)) : Nil
      redis.hset key, value
    end

    def self.retrieve(key : String) : Hash(String, String)
      redis.hgetall key
    end

    def self.delete(key : String, in ttl : Int64 = 0) : Nil
      if (ttl > 0)
        redis.expire key, ttl
      else
        redis.del key
      end
    end

    def self.delete(key : String, in ttl : Time::Span) : Nil
      delete key, ttl.to_i
    end

    def self.get(key : String, field : String) : String?
      redis.hget key, field
    end

    def self.set(key : String, field : String, value : String) : String
      redis.hset key, field, value
      value
    end

    def self.increment(key : String, field : String) : Int64
      increment key, field, by: 1
    end

    def self.increment(key : String, field : String, by value : Int32) : Int64
      redis.hincrby key, field, value
    end

    def self.expires_in(key : String) : Int64
      redis.ttl key
    end

    def self.list_queues : Array(String)
      search_queue_prefixes = QUEUES.first(2)

      search_queue_prefixes.map do |search_queue|
        key = build_key search_queue, "*"
        long_names = redis.keys key
        queue_prefix = build_key(search_queue) + ":"

        long_names.map(&.to_s).map do |long_name|
          long_name.sub(queue_prefix, "")
        end
      end.uniq.flatten
    end

    def self.list_runners : Array(String)
      runner_prefix = "mosquito:runners:"
      Redis.instance.keys("#{runner_prefix}*")
        .map(&.as(String))
        .map(&.sub(runner_prefix, ""))
    end

    # is this even a good idea?
    def self.flush : Nil
      redis.flushall
    end

    def schedule(task : Task, at scheduled_time : Time) : Task
      redis.zadd scheduled_q, scheduled_time.to_unix_ms, task.id
      task
    end

    def deschedule : Array(Task)
      time = Time.utc
      overdue_tasks = redis.zrangebyscore scheduled_q, 0, time.to_unix_ms

      return [] of Task unless overdue_tasks.any?

      overdue_tasks.compact_map do |task_id|
        redis.zrem scheduled_q, task_id
        Task.retrieve task_id.as(String)
      end
    end

    def enqueue(task : Task) : Task
      redis.lpush waiting_q, task.id
      task
    end

    def dequeue : Task?
      if id = redis.rpoplpush waiting_q, pending_q
        Task.retrieve id
      end
    end

    def finish(task : Task)
      redis.lrem pending_q, 0, task.id
    end

    def terminate(task : Task)
      redis.lpush dead_q, task.id
    end

    def flush : Nil
      redis.del(
        waiting_q,
        pending_q,
        scheduled_q,
        dead_q
      )
    end

    def size(include_dead = true) : Int64
      queues = [waiting_q, pending_q]
      queues << dead_q if include_dead

      queue_size = queues
        .map {|key| redis.llen key }
        .reduce { |sum, i| sum + i }

      scheduled_size = redis.zcount scheduled_q, 0, "+inf"
      queue_size + scheduled_size
    end

    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      def dump_{{name.id}}_q : Array(String)
        key = {{name.id}}_q
        type = redis.type key

        if type == "list"
          redis.lrange(key, 0, -1).map(&.as(String))
        elsif type == "zset"
          redis.zrange(key, 0, -1).map(&.as(String))
        elsif type == "none"
          [] of String
        else
          raise "don't know how to dump a #{type} for {{name.id}}"
        end
      end
    {% end %}

    def scheduled_task_time(task : Task) : String?
      redis.zscore scheduled_q, task.id
    end
  end
end
