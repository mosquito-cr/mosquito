module Mosquito
  alias Model = Granite::ORM::Base
  alias Id = Int64 | Int32

  struct PeriodicTask
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span

    def initialize(@class, @interval)
    end
  end

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
  end
end
