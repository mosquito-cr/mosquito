module Mosquito
  class Base
    def self.bare_mapping(&block)
      scheduled_tasks = @@scheduled_tasks
      @@scheduled_tasks = [] of PeriodicTask

      mapping = @@mapping
      @@mapping = {} of String => Job.class

      yield

    ensure
      @@mapping = mapping unless mapping.nil?
      @@scheduled_tasks = scheduled_tasks unless scheduled_tasks.nil?
    end

    def self.protect_logger(&block)
      logger = @@logger
      @@logger = Logger.new(STDOUT)

      yield

    ensure
      @@logger = logger unless logger.nil?
    end
  end
end

