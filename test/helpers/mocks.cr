# A global place for global mocks

module PerformanceCounter
  def perform
    self.class.performed!
  end

  macro included
    class_getter performances = 0

    def self.performed!
      @@performances += 1
    end

    def self.reset_performance_counter!
      @@performances = 0
    end
  end
end

class JobWithPerformanceCounter < Mosquito::Job
  include PerformanceCounter
end

class PeriodicTestJob < Mosquito::PeriodicJob
  include PerformanceCounter
end

class QueuedTestJob < Mosquito::QueuedJob
  include PerformanceCounter
  params()
end

class PassingJob < QueuedTestJob
  def perform
    super
    true
  end
end

class FailingJob < QueuedTestJob
  property fail_with_exception = false
  include PerformanceCounter
  params()

  def perform
    super

    if fail_with_exception
      raise exception_message
    else
      fail
    end
  end

  def exception_message
    "Job failed"
  end
end

class CustomRescheduleIntervalJob < PassingJob
  def reschedule_interval(retry_count)
    4.seconds
  end
end

class NonReschedulableFailingJob < FailingJob
  def rescheduleable?
    false
  end
end

class NotImplementedJob < Mosquito::Job
end

class JobWithConfig < PassingJob
  getter config = {} of String => String

  def vars_from(config : Hash(String, String))
    @config = config
  end
end

class JobWithNoParams < Mosquito::QueuedJob
  def perform
    log "no param job performed"
  end
end

class JobWithHooks < Mosquito::QueuedJob
  params(should_fail : Bool)

  before do
    log "Before Hook Executed"
  end

  after do
    log "After Hook Executed"
  end

  before do
    log "2nd Before Hook Executed"
    fail if should_fail
  end

  after do
    log "2nd After Hook Executed"
  end

  def perform
    log "Perform Executed"
  end
end

class EchoJob < Mosquito::QueuedJob
  params text : String

  def perform
    log text
  end
end

class MonthlyJob < Mosquito::PeriodicJob
  run_every 1.month

  def perform
    log "monthly task ran"
  end
end

class RateLimitedJob < Mosquito::QueuedJob
  include Mosquito::RateLimiter

  throttle key: "rate_limit", limit: Int32::MAX

  params should_fail : Bool = false, increment : Int32 = 1

  before do
    log "Before Hook Executed"
    fail if should_fail
  end

  def perform
    log "Performed"
  end

  def increment_run_count_by
    increment
  end
end

class SecondRateLimitedJob < Mosquito::QueuedJob
  include Mosquito::RateLimiter

  throttle key: "rate_limit", limit: Int32::MAX

  params()

  def perform
  end
end

Mosquito::Base.register_job_mapping "job_with_config", JobWithConfig
Mosquito::Base.register_job_mapping "job_with_performance_counter", JobWithPerformanceCounter
Mosquito::Base.register_job_mapping "failing_job", FailingJob
Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", NonReschedulableFailingJob

def task_config
  {
    "year" => "1752",
    "name" => "the year september lost 12 days",
  }
end

def create_task(type = "job_with_config", config = task_config)
  Mosquito::Task.new(type).tap do |task|
    task.config = config
    task.store
  end
end
