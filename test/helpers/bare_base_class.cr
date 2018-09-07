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
end
