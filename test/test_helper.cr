require "minitest"
require "minitest/focus"
require "minitest/autorun"

ENV["REDIS_URL"] = "redis://127.0.0.1:6379/3"

require "../mosquito"
require "./helpers/*"

Mosquito::Redis.instance.flushall

module Mosquito
  class Base
    def self.with_bare_base_class(&block)
      scheduled_tasks = @@scheduled_tasks
      @@scheduled_tasks = [] of PeriodicTask

      mapping = @@mapping
      @@mapping = {} of String => Job.class

      logger = @@logger
      @@logger = Logger.new(STDOUT)

      yield

      @@logger = logger
      @@mapping = mapping
      @@scheduled_tasks = scheduled_tasks
    end
  end

  module TestJobs
    class Periodic < PeriodicJob
      def perform; end
    end

    class Queued < QueuedJob
      def perform; end
    end
  end
end
