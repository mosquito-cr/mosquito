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
end

class QueueHookedTestJob < Mosquito::QueuedJob
  include PerformanceCounter

  property fail_before_hook = false
  property before_hook_ran = false
  property after_hook_ran = false
  property passed_job_config : Mosquito::JobRun? = nil

  before_enqueue do
    self.before_hook_ran = true
    self.passed_job_config = job

    if fail_before_hook
      false
    else
      true
    end
  end

  after_enqueue do
    self.after_hook_ran = true
    self.passed_job_config = job
  end
end


class PassingJob < QueuedTestJob
  def perform
    super
    true
  end
end

class FailingJob < QueuedTestJob
  property fail_with_exception = false
  property fail_with_retry = true
  property exception_message = "this is the reason #{name} failed"

  include PerformanceCounter

  def perform
    super

    case
    when fail_with_exception
      raise exception_message
    when ! fail_with_retry
      fail exception_message, retry: false
    else
      fail exception_message
    end
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
  param should_fail : Bool

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
  queue_name "io_queue"

  param text : String

  def perform
    log text
  end
end

class MonthlyJob < Mosquito::PeriodicJob
  run_every 1.month

  def perform
    log "monthly job_run ran"
  end
end

class RateLimitedJob < Mosquito::QueuedJob
  include Mosquito::RateLimiter

  throttle key: "rate_limit", limit: Int32::MAX

  param should_fail : Bool = false
  param increment : Int32 = 1

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

class SleepyJob < Mosquito::QueuedJob
  class_property should_sleep = true

  def perform
    while self.class.should_sleep
      sleep 0.01.seconds
    end
  end
end

class SecondRateLimitedJob < Mosquito::QueuedJob
  include Mosquito::RateLimiter

  throttle key: "rate_limit", limit: Int32::MAX

  def perform
  end
end

Mosquito::Base.register_job_mapping "job_with_config", JobWithConfig
Mosquito::Base.register_job_mapping "job_with_performance_counter", JobWithPerformanceCounter
Mosquito::Base.register_job_mapping "failing_job", FailingJob
Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", NonReschedulableFailingJob

def job_run_config
  {
    "year" => "1752",
    "name" => "the year september lost 12 days",
  }
end

def create_job_run(type = "job_with_config", config = job_run_config)
  Mosquito::JobRun.new(type).tap do |job_run|
    job_run.config = config
    job_run.store
  end
end
