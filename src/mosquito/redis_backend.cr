require "redis"
require "digest/sha1"

module Mosquito
  module Scripts
    SCRIPTS = {
      :remove_matching_key => <<-LUA
        if redis.call("get",KEYS[1]) == ARGV[1] then
            return redis.call("del",KEYS[1])
        else
            return 0
        end
      LUA
    }

    @@script_sha = {} of Symbol => String

    def self.load(connection)
      SCRIPTS.each do |name, script|
        sha = @@script_sha[name] = connection.script_load script
        Log.info { "loading script : #{name} => #{sha}" }
      end
    end

    {% for name, script in SCRIPTS %}
      @@script_sha[:{{ name.id }}] = Digest::SHA1.hexdigest({{ script }})

      @[AlwaysInline]
      def self.{{ name.id }}
        @@script_sha[:{{ name.id }}]
      end
    {% end %}
  end

  class RedisBackend < Mosquito::Backend
    LIST_OF_QUEUES_KEY = "queues"

    Log = ::Log.for(self)

    {% for name, script in Scripts::SCRIPTS %}
      def self.{{ name.id }}(*, keys = [] of String, args = [] of String, loadscripts = true)
        script = {{ script }}
        digest = Scripts.{{name.id}}
        redis.evalsha digest, keys: keys, args: args
      rescue exception : Redis::Error
        raise exception unless exception.message.try(&.starts_with? "NOSCRIPT")
        raise exception unless loadscripts

        Log.for("{{ name.id }}").warn { "Redis Scripts have gone missing, reloading" }
        Scripts.load redis
        {{ name.id }} keys: keys, args: args, loadscripts: false
      end
    {% end %}

    @[AlwaysInline]
    def self.redis
      load_scripts = @@connection.nil?

      connection = @@connection ||= ::Redis::Client.new(URI.parse(Mosquito.configuration.redis_url.to_s))

      Scripts.load(connection) if load_scripts
      connection
    end

    @[AlwaysInline]
    def redis
      self.class.redis
    end

    def initialize(name : String | Symbol)
      @name = name.to_s
    end

    def self.store(key : String, value : Hash(String, String)) : Nil
      redis.hset key, value
    end

    def self.retrieve(key : String) : Hash(String, String)
      result = redis.hgetall(key).as(Array).map(&.to_s)
      result.in_groups_of(2, "").to_h
    end

    # Overload required for crystal 1.1-1.2.
    # Soft Deprecation isn't shown, but it's here so this will get cleaned up at some point.
    # @[Deprecated("To be removed when support for 1.1 is dropped. See RedisBackend.delete(String, Int64).")]
    def self.delete(key : String, in ttl : Int32 = 0) : Nil
      delete key, in: ttl.to_i64
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
      redis.hget(key, field).as?(String)
    end

    def self.set(key : String, field : String, value : String) : String
      redis.hset key, field, value
      value
    end

    def self.increment(key : String, field : String) : Int64
      increment key, field, by: 1
    end

    def self.increment(key : String, field : String, by value : Int32) : Int64
      redis.hincrby(key, field, value).as(Int64)
    end

    def self.expires_in(key : String) : Int64
      redis.ttl key
    end

    def self.list_queues : Array(String)
      key = build_key(LIST_OF_QUEUES_KEY)
      list_queues = redis.zrange(key, 0, -1).as(Array)

      return [] of String unless list_queues.any?

      list_queues.compact_map(&.as(String))
    end

    def self.list_runners : Array(String)
      runner_prefix = "mosquito:runners:"
      Redis.instance.keys("#{runner_prefix}*")
        .map(&.as(String))
        .map(&.sub(runner_prefix, ""))
    end

    # is this even a good idea?
    def self.flush : Nil
      redis.flushdb
    end

    def self.lock?(key : String, value : String, ttl : Time::Span) : Bool
      response = redis.set key, value, ex: ttl.to_i, nx: true
      response == "OK"
    end

    def self.unlock(key : String, value : String) : Nil
      remove_matching_key keys: [key], args: [value]
    end

    def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
      redis.zadd scheduled_q, scheduled_time.to_unix_ms.to_s, job_run.id
      job_run
    end

    def deschedule : Array(JobRun)
      time = Time.utc
      overdue_job_runs = redis.zrangebyscore(scheduled_q, "0", time.to_unix_ms.to_s).as(Array)

      return [] of JobRun unless overdue_job_runs.any?

      overdue_job_runs.compact_map do |job_run_id|
        redis.zrem scheduled_q, job_run_id.to_s
        JobRun.retrieve job_run_id.as(String)
      end
    end

    def enqueue(job_run : JobRun) : JobRun
      redis.pipeline do |pipe|
        # Pushes the job onto the waiting queue.
        pipe.lpush waiting_q, job_run.id

        # Updates the list of queues to include the current queue
        pipe.zadd build_key(LIST_OF_QUEUES_KEY), Time.utc.to_unix.to_s, name
      end
      job_run
    end

    def dequeue : JobRun?
      if id = redis.lmove waiting_q, pending_q, :right, :left
        JobRun.retrieve id.to_s
      end
    end

    def finish(job_run : JobRun)
      redis.lrem pending_q, 0, job_run.id
    end

    def terminate(job_run : JobRun)
      redis.lpush dead_q, job_run.id
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
        .map { |key| redis.llen(key).as(Int64) }
        .reduce { |sum, i| sum + i }

      scheduled_size = redis.zcount scheduled_q, "0", "+inf"
      queue_size + scheduled_size.as(Int64)
    end

    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      def dump_{{name.id}}_q : Array(String)
        key = {{name.id}}_q
        type = redis.type key

        if type == "list"
          redis.lrange(key, "0", "-1").as(Array(Redis::Value)).map(&.as(String))
        elsif type == "zset"
          redis.zrange(key, 0, -1).as(Array(Redis::Value)).map(&.as(String))
        elsif type == "none"
          [] of String
        else
          raise "don't know how to dump a #{type} for {{name.id}}"
        end
      end
    {% end %}

    def scheduled_job_run_time(job_run : JobRun) : String?
      redis.zscore(scheduled_q, job_run.id).as?(String)
    end
  end
end
