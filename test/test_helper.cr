require "minitest"
require "minitest/focus"
require "minitest/autorun"

ENV["REDIS_URL"] = "redis://127.0.0.1:6379/3"

require "../mosquito"

Mosquito::Redis.instance.flushall


module Mosquito
  def self.memory_logger
    @@memory_logger ||= IO::Memory.new
  end
end

Mosquito::Base.logger = Logger.new Mosquito.memory_logger

class Minitest::Test
  def logs
    Mosquito.memory_logger.rewind
    Mosquito.memory_logger.gets_to_end
  end

  def clear_logs
    Mosquito.memory_logger.clear
  end
end
