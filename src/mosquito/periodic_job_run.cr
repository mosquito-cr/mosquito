module Mosquito
  class PeriodicJobRun
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span | Time::MonthSpan
    property last_executed_at : Time

    def initialize(@class, @interval)
      @last_executed_at = Time.unix 0
    end

    def try_to_execute : Bool
      now = Time.utc

      if last_executed_at + interval <= now
        execute
        @last_executed_at = now
        true
      else
        false
      end
    end

    def execute
      job = @class.new
      job_run = job.build_job_run
      job_run.store
      @class.queue.enqueue job_run
    end
  end
end
