require "./logger"

module Mosquito
  abstract class Job
    def puts(message)
      print "#{message}\n"
    end

    def print(message)
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
    rescue e
      puts "Job failed! Raised #{e.class}: #{e.message}"
      e.backtrace.each do |trace|
        puts trace
      end

      @succeeded = false
    end

    def perform
      puts "No job definition found for #{self.class.name}"
      fail
    end

    def fail
      raise JobFailed.new
    end

    def executed?
      @executed
    end

    def succeeded?
      raise "Job hasn't been executed yet" unless @executed
      @succeeded
    end

    def failed?
      ! succeeded?
    end
  end

  class JobFailed < Exception
  end

  class DoubleRun < Exception
  end
end
