require "./log"
require "./serializers/*"

module Mosquito
  # A Job is a definition for work to be performed.
  # Jobs are pieces of code which run a Task.
  #
  # - Jobs prevent double execution of a job for a task
  # - Jobs Rescue when a #perform method fails a task for any reason
  # - Jobs can be rescheduleable
  abstract class Job
    Log = Mosquito::Log.for(self)

    include Mosquito::Serializers::Primitives

    def log(message)
      Log.info { message }
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
    else
      @succeeded = true
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
    def executed? : Bool
      @executed
    end

    # Did the job run and succeed?
    def succeeded? : Bool
      raise "Job hasn't been executed yet" unless @executed
      @succeeded
    end

    # Did the job run and fail?
    def failed? : Bool
      !succeeded?
    end

    # abstract, override if desired.
    #
    # True if this job is rescheduleable, false if not.
    def rescheduleable? : Bool
      true
    end

    # abstract, override if desired.
    #
    # For a given retry count, is this job rescheduleable?
    def rescheduleable?(retry_count : Int32) : Bool
      rescheduleable? && retry_count < 5
    end

    # abstract, override if desired.
    #
    # For a given retry count, how long should the delay between
    # job attempts be?
    def reschedule_interval(retry_count : Int32) : Time::Span
      2.seconds * (retry_count ** 2)
      # retry 1 = 2 minutes
      #       2 = 8
      #       3 = 18
      #       4 = 32
    end

  end
end
