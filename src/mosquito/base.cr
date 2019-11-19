require "habitat"

module Mosquito
  alias Model = Granite::Base
  alias Id = Int64 | Int32

  class Base
    class_getter mapping = {} of String => Mosquito::Job.class
    class_getter scheduled_tasks = [] of PeriodicTask
    class_getter timetable = [] of PeriodicTask

    def self.register_job_mapping(string, klass)
      @@mapping[string] = klass
    end

    def self.job_for_type(type : String) : Mosquito::Job.class
      @@mapping[type]
    rescue e : KeyError
      error = <<-TEXT
      Could not find a job class for type #{type}, perhaps you forgot to register it?

      Current known types are:

      TEXT

      error += @@mapping.keys.map { |k| "- #{k}" }.join "\n"
      error += "\n\n"

      raise KeyError.new(error)
    end

    def self.register_job_interval(klass, interval : Time::Span)
      @@scheduled_tasks << PeriodicTask.new(klass, interval)
    end

    def self.register_job(klass, *, to_run_at scheduled_time : Time)
      position = @@timetable.index do
      end
    end

    def self.logger
      @@logger ||= Logger.new(STDOUT)
    end

    def self.logger=(@@logger : Logger | ::Logger)
    end

    def self.log(*messages)
      logger.log(Logger::Severity::INFO, messages.join(" "))
    end

    Habitat.create do
      setting redis_url : String

      # Optionally add examples to settings that appear in error messages
      # when the value is not set.
      #
      # Use `String#dump` when you want the example to be wrapped in quotes
      setting redis_url : String, example: "redis://localhost:6379"
    end

    Habitat.raise_if_missing_settings!
  end
end
