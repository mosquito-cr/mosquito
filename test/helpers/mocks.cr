# A global place for global mocks

class PassingJob < Mosquito::Job
  def perform
    true
  end
end

class FailingJob < Mosquito::Job
  def perform
    if fail_with_exception
      raise exception_message
    else
      fail
    end
  end

  def exception_message
    "Job failed"
  end

  property fail_with_exception = false
end

class NotImplementedJob < Mosquito::Job
end

class JobWithPerformanceCounter < Mosquito::Job
  def perform
    self.class.performed!
  end

  class_getter performances = 0
  def self.performed!
    @@performances += 1
  end

  def self.reset_performance_counter!
    @@performances = 0
  end
end

class JobWithConfig < Mosquito::Job
  def perform
  end

  getter config = {} of String => String

  def vars_from(config : Hash(String, String))
    @config = config
  end
end

Mosquito::Base.register_job_mapping "job_with_config", JobWithConfig
Mosquito::Base.register_job_mapping "job_with_performance_counter", JobWithPerformanceCounter
Mosquito::Base.register_job_mapping "failing_job", FailingJob

def task_config
  {
    "year" => "1752",
    "name" => "the year september lost 12 days"
  }
end

def create_task(type = "job_with_config", config = task_config)
  Mosquito::Task.new(type).tap do |task|
    task.config = config
    task.store
  end
end
