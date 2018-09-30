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

    getter queues

    def initialize
      @queues = [] of Queue
      @start_time = 0_i64
      @execution_timestamps = {} of Symbol => Time
    end

    def run
      start_time
      fetch_queues
      enqueue_periodic_tasks
      enqueue_delayed_tasks
      dequeue_and_run_tasks
      idle_wait
    end

    private def start_time
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

      if delta > interval
        @execution_timestamps[name] = now
        yield now
      end
    end

    private def fetch_queues
      run_at_most every: 0.25.seconds, label: :fetch_queues do |t|
        @queues = Queue.list_queues.map { |name| Queue.new name }
      end
    end

    private def enqueue_periodic_tasks
      run_at_most every: 1.second, label: :enqueue_periodic_tasks do |now|
        Base.scheduled_tasks.each do |scheduled_task|
          scheduled_task.try_to_execute
        end
      end
    end

    private def enqueue_delayed_tasks
      run_at_most every: 1.second, label: :enqueue_delayed_tasks do |t|
        queues.each do |q|
          overdue_tasks = q.dequeue_scheduled
          next unless overdue_tasks.any?
          Base.log "Found #{overdue_tasks.size} delayed tasks"

          overdue_tasks.each do |task|
            q.enqueue task
          end
        end
      end
    end

    private def dequeue_and_run_tasks
      queues.each do |q|
        run_next_task q
      end
    end

    private def run_next_task(q : Queue)
      task = q.dequeue
      return unless task

      Base.log "#{"Running".colorize.magenta} task #{task} from #{q.name}"

      bench = Benchmark.measure do
        task.run
      end

      if bench.total > 0.1
        time = "#{(bench.total).*(100).trunc./(100)}s".colorize.red
      elsif bench.total > 0.001
        time = "#{(bench.total * 1_000).trunc}ms".colorize.yellow
      elsif bench.total > 0.000_001
        time = "#{(bench.total * 100_000).trunc}µs".colorize.green
      elsif bench.total > 0.000_000_001
        time = "#{(bench.total * 1_000_000_000).trunc}ns".colorize.green
      else
        time = "no discernible time at all".colorize.green
      end

      if task.succeeded?
        Base.log "#{"Success:".colorize.green} task #{task} finished and took #{time}"
        q.forget task
        task.delete
      else
        message = "#{"Failure:".colorize.red} task #{task} failed, taking #{time}"

        if task.rescheduleable?
          interval = task.reschedule_interval
          next_execution = Time.now + interval
          Base.log "#{message} and #{"will run again".colorize.cyan} in #{interval} (at #{next_execution})"
          q.reschedule task, next_execution
        else
          Base.log "#{message} and #{"cannot be rescheduled".colorize.yellow}"
          q.banish task
        end
      end
    end
  end
end
