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

module Mosquito
  module TestJobs
    class Periodic < PeriodicJob
      include PerformanceCounter
    end

    class Queued < QueuedJob
      include PerformanceCounter
      params()
    end

    class CustomRescheduleIntervalJob < ::JobWithPerformanceCounter
      def reschedule_interval(retry_count)
        4.seconds
      end
    end
  end
end

class PassingJob < Mosquito::QueuedJob
  include PerformanceCounter
  params()

  def perform
    super
    true
  end
end

class FailingJob < Mosquito::QueuedJob
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

  property fail_with_exception = false
end

class NonReschedulableFailingJob < Mosquito::QueuedJob
  include PerformanceCounter
  params()

  def perform
    super
    fail
  end

  def rescheduleable?
    false
  end
end

class NotImplementedJob < Mosquito::Job
end

class JobWithConfig < Mosquito::Job
  def perform
  end

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

class JobWithBeforeHook < Mosquito::QueuedJob
  params(should_fail : Bool)

  before do
    log "Before Hook Executed"
  end

  before do
    log "2nd Before Hook Executed"
    fail if should_fail
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

Mosquito::Base.register_job_mapping "job_with_config", JobWithConfig
Mosquito::Base.register_job_mapping "job_with_performance_counter", JobWithPerformanceCounter
Mosquito::Base.register_job_mapping "failing_job", FailingJob
Mosquito::Base.register_job_mapping "non_reschedulable_failing_job", FailingJob

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
