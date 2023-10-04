module Mosquito
  class PeriodicJobRun
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span | Time::MonthSpan

    def last_executed_at?
      if timestamp = @metadata["last_executed_at"]?
        Time.unix(timestamp.to_i)
      else
        nil
      end
    end

    # todo add tests for this distributed tracking
    def last_executed_at
      last_executed_at? || Time.unix(0)
    end

    def last_executed_at=(time : Time)
      @metadata["last_executed_at"] = time.to_unix.to_s

      case interval_ = interval
      when Time::Span
        @metadata.delete(in: interval_ * 3)
      when Time::MonthSpan
        seconds_in_an_average_month = 2_635_200.seconds
        @metadata.delete(in: seconds_in_an_average_month * interval_.value * 3)
      end
    end

    def initialize(@class, @interval)
      @metadata = Metadata.new(Backend.build_key("periodic_jobs", @class.name))
    end

    def try_to_execute : Bool
      now = Time.utc

      if last_executed_at + interval <= now
        execute

        self.last_executed_at = now
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
