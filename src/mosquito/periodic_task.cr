module Mosquito
  class PeriodicJobRun
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span
    property last_executed_at : Time

    def initialize(@class, @interval)
      @last_executed_at = Time.unix 0
    end

    def try_to_execute : Nil
      now = Time.utc

      if now - last_executed_at >= interval
        execute
        @last_executed_at = now
      end
    end

    def execute
      job = @class.new
      job_run = job.build_run
      job_run.store
      @class.queue.enqueue job_run
    end
  end
end
