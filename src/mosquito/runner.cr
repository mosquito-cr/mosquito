require "benchmark"

module Mosquito
  class Runner
    include Logger

    # Minimum time in seconds to wait between checking for jobs in redis.
    IDLE_WAIT = 15

    def self.start
      new.run
    end

    getter queues
    @last_run_epoch : Int64

    def initialize
      @queues = [] of Queue
      @last_run_epoch = Int64.new(0)
      @start_time = 0_i64
    end

    def run
      log "Mosquito is buzzing..."

      while true
        start_time
        fetch_queues
        enqueue_periodic_tasks
        enqueue_delayed_tasks
        dequeue_and_run_tasks
        idle_wait
      end
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

    private def fetch_queues
      new_queues = Queue.list_queues.map { |name| Queue.new name }

      if new_queues != @queues
        if new_queues.any?
          log "Queues: #{new_queues.map(&.name).join(", ")}"
        end

        @queues = new_queues
      end
    end

    private def enqueue_periodic_tasks
      now = Time.now.epoch
      # only enqueue tasks at most once a minute
      return unless now - @last_run_epoch > 60
      @last_run_epoch = now

      # roughly the number of minutes since the epoch
      moment = now / 60

      Base.scheduled_tasks.each do |scheduled_task|
        if moment % scheduled_task.interval.minutes == 0
          job = scheduled_task.class.new
          task = job.build_task
          task.store
          scheduled_task.class.queue.enqueue task
        end
      end
    end

    private def enqueue_delayed_tasks
      queues.each do |q|
        overdue_tasks = q.dequeue_scheduled
        next unless overdue_tasks.any?
        log "Found #{overdue_tasks.size} delayed tasks"

        overdue_tasks.each do |task|
          q.enqueue task
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

      log "Running task #{task} from #{q.name}"

      bench = Benchmark.measure do
        task.run
      end

      took = "took #{bench.total} seconds"

      if task.succeeded?
        log "task #{task} succeeded, #{took}"
        q.forget task
        task.delete
      else
        message = "task #{task} failed, #{took}"

        if task.rescheduleable?
          interval = task.reschedule_interval
          next_execution = Time.now + interval
          log "#{message} rescheduling for #{next_execution} (#{interval})"
          q.reschedule task, next_execution
        else
          log "#{message} cannot reschedule"
          q.banish task
        end
      end
    end
  end
end
