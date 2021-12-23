require "redis"

module Mosquito
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
