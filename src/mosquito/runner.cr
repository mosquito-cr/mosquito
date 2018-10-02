require "benchmark"
require "colorize"

module Mosquito
  class Runner
    # Minimum time in seconds to wait between checking for jobs in redis.
    IDLE_WAIT = 0.1

    def self.start
      Base.log "Mosquito is buzzing..."
      instance = new

      while true
        instance.run
      end
    end

    getter queues, start_time

    def initialize
      @queues = [] of Queue
      @start_time = 0_i64
      @execution_timestamps = {} of Symbol => Time
    end

    def run
      set_start_time
      fetch_queues
      enqueue_periodic_tasks
      enqueue_delayed_tasks
      dequeue_and_run_tasks
      idle_wait
    end

    private def set_start_time
      @start_time = Time.now.epoch
    end

    private def idle_wait
      delta = Time.now.epoch - @start_time
      if delta < IDLE_WAIT
        sleep(IDLE_WAIT - delta)
      end
    end

    private def run_at_most(*, every interval, label name, &block)
      now = Time.now
      last_execution = @execution_timestamps[name]? || Time.epoch 0
      delta = now - last_execution

      if delta >= interval
        @execution_timestamps[name] = now
        yield now
      end
    end

    macro throttled_def(name, run_every, &block)
      private def {{ name.id }}
        run_at_most every: {{ run_every.id }}, label: :{{ name.id }} do
          {{ yield }}
        end
      end
    end

    throttled_def fetch_queues, 0.25.seconds do
      @queues = Queue.list_queues.map { |name| Queue.new name }
    end

    throttled_def enqueue_periodic_tasks, 1.second do
      Base.scheduled_tasks.each do |scheduled_task|
        scheduled_task.try_to_execute
      end
    end

    throttled_def enqueue_delayed_tasks, 1.second do
      queues.each do |q|
        overdue_tasks = q.dequeue_scheduled
        next unless overdue_tasks.any?
        Base.log "Found #{overdue_tasks.size} delayed tasks"

        overdue_tasks.each do |task|
          q.enqueue task
        end
      end
    end

    private def dequeue_and_run_tasks
      queues.each do |q|
        if task = q.dequeue
          Base.log start_message(task, q)
          task.run

          if task.succeeded?
            Base.log success_message(task)
            q.forget task
            task.delete
          else
            if task.rescheduleable?
              Base.log failure_message(task)
              q.reschedule task, task.reschedule_interval.from_now
            else
              Base.log fatal_message(task)
              q.banish task
            end
          end

        end
      end
    end

    private def start_message(task : Task, q : Queue)
      String.build do |s|
        s << "Running".colorize.magenta
        s << " task #{task}"
        s << " from #{q.name}"
      end
    end

    private def success_message(task : Task)
      String.build do |s|
        s << "Success:".colorize.green
        s << " task #{task} finished and took "
        s << present_time task.runtime
      end
    end

    private def failure_message(task : Task)
      String.build do |s|
        s << "Failure:".colorize.red
        s << "task #{task} failed, taking "
        s << present_time task.runtime
        s << " and "
        s << "will run again".colorize.cyan

        interval = task.reschedule_interval
        next_execution = Time.now + interval
        s << " in #{interval} (at #{next_execution})"
      end
    end

    private def fatal_message(task : Task)
      String.build do |s|
        s << "Failure:".colorize.red
        s << " task #{task} failed, taking "
        s << present_time task.runtime
        s << " and "
        s << "cannot be rescheduled".colorize.yellow
      end
    end

    private def present_time(t)
      if t > 0.1
        "#{t.*(100).trunc./(100)}s".colorize.red
      elsif t > 0.001
        "#{(t * 1_000).trunc}ms".colorize.yellow
      elsif t > 0.000_001
        "#{(t * 100_000).trunc}µs".colorize.green
      elsif t > 0.000_000_001
        "#{(t * 1_000_000_000).trunc}ns".colorize.green
      else
        "no discernible time at all".colorize.green
      end
    end
  end
end
