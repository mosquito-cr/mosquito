require "./logger"

module Mosquito
  # A Job is a definition for work to be performed.
  # Jobs are pieces of code which run a Task.
  #
  # - Jobs prevent double execution of a job for a task
  # - Jobs Rescue when a #perform method fails a task for any reason
  # - Jobs can be rescheduleable
  abstract class Job
    def log(message)
      Base.log "[#{self.class.name}-#{task_id}] #{message}"
    end

    getter executed = false
    getter succeeded = false

    property task_id : String?

    def self.job_type : String
      ""
    end

    def self.queue
      if job_type.blank?
        Queue.new("default")
      else
        Queue.new(job_type)
      end
    end

    def run
      raise DoubleRun.new if executed
      @executed = true
      perform
      @succeeded = true
    rescue JobFailed
      @succeeded = false
    rescue e : DoubleRun
      raise e
    rescue e
      log "Job failed! Raised #{e.class}: #{e.message}"
      e.backtrace.each do |trace|
        log trace
      end

      @succeeded = false
    end

    # abstract, override in a Job descendant to do something productive
    def perform
      log "No job definition found for #{self.class.name}"
      fail
    end

    # To be called from inside a #perform
    # Marks this job as a failure. If the job is a candidate for
    # re-scheduling, it will be run again at a later time.
    def fail
      raise JobFailed.new
    end

    # Did the job execute?
    def executed?
      @executed
    end

    # Did the job run and succeed?
    def succeeded?
      raise "Job hasn't been executed yet" unless @executed
      @succeeded
    end

    # Did the job run and fail?
    def failed?
      ! succeeded?
    end

    # abstract, override if desired.
    def rescheduleable?
      true
    end
  end
end
