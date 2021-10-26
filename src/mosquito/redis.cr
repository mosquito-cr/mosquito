require "redis"

module Mosquito
  class Redis
    def self.instance
      @@instance ||= new
    end

    def initialize
      Mosquito.validate_settings

      @connection = ::Redis.new url: Mosquito.settings.redis_url
    end

    @[Deprecated]
    def store_hash(name : String, hash : Hash(String, String))
      hset name, hash
    end

    @[Deprecated]
    def retrieve_hash(name : String) : Hash(String, String)
      hgetall name
    end

    forward_missing_to @connection
  end
end
