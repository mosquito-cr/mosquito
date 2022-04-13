module Mosquito
  alias Id = Int64 | Int32

  class Base
    Log = ::Log.for(self)

    class_getter mapping = {} of String => Mosquito::Job.class
    class_getter scheduled_tasks = [] of PeriodicTask
    class_getter timetable = [] of PeriodicTask

    def self.register_job_mapping(string, klass)
      @@mapping[string] = klass
    end

    def self.job_for_type(type : String) : Mosquito::Job.class | Nil
      @@mapping[type]
    rescue e : KeyError
      Log.error {
        error = "Could not find a job class for type '#{type}'. Known types are: "
        error += @@mapping.keys.join ", "
      }
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
