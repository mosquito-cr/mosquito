module Mosquito
  alias Model = Granite::Base
  alias Id = Int64 | Int32

  class Base
    @@mapping = {} of String => Mosquito::Job.class
    class_getter scheduled_tasks = [] of PeriodicTask

    def self.register_job_mapping(string, klass)
      @@mapping[string] = klass
    end

    def self.job_for_type(type : String) : Mosquito::Job.class
      @@mapping[type]
    end

    def self.register_job_interval(klass, interval : Time::Span)
      @@scheduled_tasks << PeriodicTask.new(klass, interval)
    end

    def self.logger
      @@logger ||= Logger.new(STDOUT)
    end

    def self.log(*messages)
      logger.log(Logger::Severity::INFO, messages.join(" "))
    end
  end
end
