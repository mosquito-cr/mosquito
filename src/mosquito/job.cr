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

    class_getter config : Hash(String, String) = {"limit" => "0", "period" => "0", "executed" => "0", "next_batch" => "0", "last_executed" => "0"}

    def log(message)
      Log.for(self.class).info { message }
    end

    getter executed = false
    getter succeeded = false

    property task_id : String?

    macro throttle(limit, period)
      @@config["limit"] = {{limit.stringify}}
      @@config["period"] = {{period.stringify}}
    end

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
      increment
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
    def rescheduleable? : Bool
      true
    end

    # Handles throttling logic
    private def increment : Nil
      redis = Redis.instance
      q = self.class.queue.config_q
      redis.hincrby q, "executed", 1
      config = redis.retrieve_hash q
      return if config["limit"] == "0" && config["period"] == "0"

      if config["executed"] == config["limit"]
        next_batch = (Time.utc + config["period"].to_i.seconds)
        redis.hset q, "executed", 0
        redis.hset q, "next_batch", next_batch.to_unix
        log "#{"Execution limit reached".colorize.yellow} #{"next_batch".colorize.cyan} in #{config["period"].to_i.seconds} (at #{next_batch})"
      end
      redis.hset q, "last_executed", Time.utc.to_unix
    end
  end
end
