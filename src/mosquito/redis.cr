require "redis"

module Mosquito
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
