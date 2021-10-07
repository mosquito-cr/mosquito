require "redis"

module Mosquito
  class RedisBackend
    include Mosquito::Backend

    ID_PREFIX = {"mosquito"}
    QUEUES    = %w(waiting scheduled pending dead config)

    {% for q in QUEUES %}
      def {{q.id}}_q(name : String)
        redis_key ID_PREFIX, {{q}}, name
      end
    {% end %}

    def redis_key(*parts)
      Redis.key *parts
    end


    def store_job_config(job : Mosquito::Job.class) : Nil
      Redis.instance.store_hash(job.queue.config_q, job.config)
    end

    def schedule(queue_name : String, task : Task, at scheduled_time : Time)
      Redis.instance.zadd scheduled_q(queue_name), scheduled_time.to_unix_ms, task.id
    end

    def deschedule(queue_name : String) : Array(Task)
      time = Time.utc
      overdue_tasks = Redis.instance.zrangebyscore scheduled_q(queue_name), 0, time.to_unix_ms

      return [] of Task unless overdue_tasks.any?

      overdue_tasks.map do |task_id|
        Redis.instance.zrem scheduled_q(queue_name), task_id
        Task.retrieve task_id.as(String)
      end.compact
    end

    def enqueue(queue_name : String, task : Task)
      Redis.instance.lpush waiting_q(queue_name), task.id
    end

    def dequeue(queue_name : String) : Task?
      if id = Redis.instance.rpoplpush waiting_q(queue_name), pending_q(queue_name)
        Task.retrieve id
      end
    end

    def finish(queue_name : String, task : Task)
      Redis.instance.lrem pending_q(queue_name), 0, task.id
    end

    def terminate(queue_name : String, task : Task)
      Redis.instance.lpush dead_q(queue_name), task.id
    end

    def flush(queue_name : String)
      Redis.instance.del(
        waiting_q(queue_name),
        pending_q(queue_name),
        scheduled_q(queue_name),
        dead_q(queue_name)
      )
    end
  end

  class Redis
    class KeyBuilder
      KEY_SEPERATOR = ":"

      def self.build(*parts)
        id = [] of String

        parts.each do |part|
          case part
          when String
            id << part
          when Array
            part.each do |e|
              id << build e
            end
          when Tuple
            id << build part.to_a
          else
            id << "invalid_key_part"
          end
        end

        id.flatten.join KEY_SEPERATOR
      end
    end

    def self.instance
      @@instance ||= new
    end

    def initialize
      Mosquito.validate_settings

      @connection = ::Redis.new url: Mosquito.settings.redis_url
    end

    def self.key(*parts)
      KeyBuilder.build *parts
    end

    def store_hash(name : String, hash : Hash(String, String))
      hset(name, hash)
    end

    def retrieve_hash(name : String) : Hash(String, String)
      hgetall(name)
    end

    forward_missing_to @connection
  end
end
