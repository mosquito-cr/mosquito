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

    forward_missing_to @connection
  end
end
