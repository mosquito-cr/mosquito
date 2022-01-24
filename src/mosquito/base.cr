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

    def self.register_job_interval(klass, interval : Time::Span | Time::MonthSpan)
      @@scheduled_tasks << PeriodicTask.new(klass, interval)
    end

    def self.register_job(klass, *, to_run_at scheduled_time : Time)
      position = @@timetable.index do
      end
    end
  end
end
