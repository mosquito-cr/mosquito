require "redis"

module Mosquito
  module RedisInterface
    abstract def del(key)
    abstract def expire(key, seconds)
    abstract def flushall
    abstract def hget(key, field)
    abstract def hgetall(key)
    abstract def hincrby(key, field, increment)
    abstract def hset(key, field, value)
    abstract def keys(pattern)
    abstract def llen(key)
    abstract def lpush(key, value)
    abstract def lrem(key, count, value)
    abstract def rpoplpush(source, destination)
    abstract def ttl(key)
    abstract def zadd(key, score, value)
    abstract def zcount(key, min, max)
    abstract def zrangebyscore(key, min, max)
    abstract def zrem(key, value)
  end

  class Redis
    def self.instance
      @@instance ||= new
    end

    def initialize
      Mosquito.configuration.validate

      @connection = ::Redis::PooledClient.new url: Mosquito.configuration.redis_url
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
