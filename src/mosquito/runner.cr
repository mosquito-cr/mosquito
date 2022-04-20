require "colorize"

module Mosquito
  class Runner
    Log = ::Log.for self

    # Minimum time in seconds to wait between checking for jobs.
    property idle_wait : Float64

    # How long a job config is persisted after success
    property successful_job_ttl : Int32

    # How long a job config is persisted after failure
    property failed_job_ttl : Int32

    # Should the worker continue working?
    class_property keep_running : Bool = true

    getter queues, start_time

    def self.start
      Log.notice { "Mosquito is buzzing..." }
      instance = new

      while true
        instance.run
        break unless @@keep_running
      end
    end

    def self.stop
      Log.notice { "Mosquito is shutting down..." }
      @@keep_running = false
    end

    def initialize
      Mosquito.validate_settings

      @idle_wait = Mosquito.settings.idle_wait
      @successful_job_ttl = Mosquito.settings.successful_job_ttl
      @failed_job_ttl = Mosquito.settings.failed_job_ttl

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
      idle
    end

    private def set_start_time
      @start_time = Time.utc.to_unix
    end

    private def idle
      delta = Time.utc.to_unix - @start_time
      if delta < idle_wait
        sleep(idle_wait - delta)
      end
    end

    private def run_at_most(*, every interval, label name, &block)
      now = Time.utc
      last_execution = @execution_timestamps[name]? || Time.unix 0
      delta = now - last_execution

      if delta >= interval
        @execution_timestamps[name] = now
        yield now
      end
    end

    private def fetch_queues
      run_at_most every: 0.25.seconds, label: :fetch_queues do |t|
        candidate_queues = Mosquito.backend.list_queues.map { |name| Queue.new name }
        @queues = filter_queues(candidate_queues)

        Log.for("fetch_queues").debug {
          if @queues.size > 0
            "found #{@queues.size} queues: #{@queues.map(&.name).join(", ")}"
          end
        }
      end
    end

    private def filter_queues(present_queues : Array(Mosquito::Queue))
      permitted_queues = Mosquito.settings.run_from
      return present_queues if permitted_queues.empty?
      filtered_queues = present_queues.select do |queue|
        permitted_queues.includes? queue.name
      end

      Log.for("filter_queues").debug {
        if filtered_queues.empty?
          filtered_out_queues = present_queues - filtered_queues

          if filtered_out_queues.size > 0
            "No watchable queues found. Ignored #{filtered_out_queues.size} queues not configured to be watched: #{filtered_out_queues.map(&.name).join(", ")}"
          end
        end
      }

      filtered_queues
    end

    private def enqueue_periodic_tasks
      return unless Mosquito.settings.run_cron_scheduler

      run_at_most every: 1.second, label: :enqueue_periodic_tasks do |now|
        Base.scheduled_tasks.each do |scheduled_task|
          enqueued = scheduled_task.try_to_execute

          Log.for("enqueue_periodic_tasks").debug {
            "enqueued #{scheduled_task.class}" if enqueued
          }
        end
      end
    end

    private def enqueue_delayed_tasks
      run_at_most every: 1.second, label: :enqueue_delayed_tasks do |t|

        queues.each do |q|
          overdue_tasks = q.dequeue_scheduled
          next unless overdue_tasks.any?
          Log.for("enqueue_delayed_tasks").info { "Found #{overdue_tasks.size} delayed tasks in #{q.name}" }

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

      Log.notice { "#{"Starting:".colorize.magenta} #{task} from #{q.name}" }

      duration = Time.measure do
        task.run
      end.total_seconds

      if task.succeeded?
        Log.notice { "#{"Success:".colorize.green} #{task} finished and took #{time_with_units duration}" }
        q.forget task
        task.delete in: successful_job_ttl

      else
        if task.rescheduleable?
          next_execution = Time.utc + task.reschedule_interval

          Log.notice {
            String.build do |s|
              s << "Failure: ".colorize.red
              s << task
              s << " failed, taking "
              s << time_with_units duration
              s << " and "
              s << "will run again".colorize.cyan
              s << " in "
              s << task.reschedule_interval
              s << " (at "
              s << next_execution
              s << ")"
            end
          }

          q.reschedule task, next_execution
        else
          Log.notice {
            String.build do |s|
              s << "Failure: ".colorize.red
              s << task
              s << " failed, taking "
              s << time_with_units duration
              s << " and "
              s << "cannot be rescheduled".colorize.yellow
            end
          }

          q.banish task
          task.delete in: failed_job_ttl
        end
      end
    end

    private def time_with_units(seconds : Float64)
      if seconds > 0.1
        "#{(seconds).*(100).trunc./(100)}s".colorize.red
      elsif seconds > 0.001
        "#{(seconds * 1_000).trunc}ms".colorize.yellow
      elsif seconds > 0.000_001
        "#{(seconds * 100_000).trunc}µs".colorize.green
      elsif seconds > 0.000_000_001
        "#{(seconds * 1_000_000_000).trunc}ns".colorize.green
      else
        "no discernible time at all".colorize.green
      end
    end
  end
end
