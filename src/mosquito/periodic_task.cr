module Mosquito
  class PeriodicTask
    property class : Mosquito::PeriodicJob.class
    property interval : Time::Span
    property last_executed_at : Time

    def initialize(@class, @interval)
      @last_executed_at = Time.unix 0
    end

    def try_to_execute : Nil
      now = Time.now

      if now - last_executed_at >= interval
        execute
        @last_executed_at = now
      end
    end

    def execute
      job = @class.new
      task = job.build_task
      task.store
      @class.queue.enqueue task
    end
  end
end
