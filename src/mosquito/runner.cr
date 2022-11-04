require "colorize"

module Mosquito
  class Runner
    Log = ::Log.for self

    # Minimum time in seconds to wait between checking for jobs.
    property idle_wait : Time::Span

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

      while @@keep_running
        instance.run
      end
    end

    def self.stop
      Log.notice { "Mosquito is shutting down..." }
      @@keep_running = false
    end

    def initialize
      Mosquito.configuration.validate

      @idle_wait = Mosquito.configuration.idle_wait
      @successful_job_ttl = Mosquito.configuration.successful_job_ttl
      @failed_job_ttl = Mosquito.configuration.failed_job_ttl

      @queues = [] of Queue
      @start_time = 0.seconds
      @execution_timestamps = {} of Symbol => Time
    end

    def run
      set_start_time
      fetch_queues
      enqueue_periodic_job_runs
      enqueue_delayed_job_runs
      dequeue_and_run_job_runs
      idle
    end

    private def set_start_time
      @start_time = Time.monotonic
    end

    private def idle
      delta = Time.monotonic - @start_time
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
      permitted_queues = Mosquito.configuration.run_from
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

    private def enqueue_periodic_job_runs
      return unless Mosquito.configuration.run_cron_scheduler

      run_at_most every: 1.second, label: :enqueue_periodic_job_runs do |now|
        Base.scheduled_job_runs.each do |scheduled_job_run|
          enqueued = scheduled_job_run.try_to_execute

          Log.for("enqueue_periodic_job_runs").debug {
            "enqueued #{scheduled_job_run.class}" if enqueued
          }
        end
      end
    end

    private def enqueue_delayed_job_runs
      run_at_most every: 1.second, label: :enqueue_delayed_job_runs do |t|

        queues.each do |q|
          overdue_job_runs = q.dequeue_scheduled
          next unless overdue_job_runs.any?
          Log.for("enqueue_delayed_job_runs").info { "Found #{overdue_job_runs.size} delayed job runs in #{q.name}" }

          overdue_job_runs.each do |job_run|
            q.enqueue job_run
          end
        end
      end
    end

    private def dequeue_and_run_job_runs
      queues.each do |q|
        run_next_job_run q
      end
    end

    private def run_next_job_run(q : Queue)
      job_run = q.dequeue
      return unless job_run

      Log.notice { "#{"Starting:".colorize.magenta} #{job_run} from #{q.name}" }

      duration = Time.measure do
        job_run.run
      end.total_seconds

      if job_run.succeeded?
        Log.notice { "#{"Success:".colorize.green} #{job_run} finished and took #{time_with_units duration}" }
        q.forget job_run
        job_run.delete in: successful_job_ttl

      else
        if job_run.rescheduleable?
          next_execution = Time.utc + job_run.reschedule_interval

          Log.notice {
            String.build do |s|
              s << "Failure: ".colorize.red
              s << job_run
              s << " failed, taking "
              s << time_with_units duration
              s << " and "
              s << "will run again".colorize.cyan
              s << " in "
              s << job_run.reschedule_interval
              s << " (at "
              s << next_execution
              s << ")"
            end
          }

          q.reschedule job_run, next_execution
        else
          Log.notice {
            String.build do |s|
              s << "Failure: ".colorize.red
              s << job_run
              s << " failed, taking "
              s << time_with_units duration
              s << " and "
              s << "cannot be rescheduled".colorize.yellow
            end
          }

          q.banish job_run
          job_run.delete in: failed_job_ttl
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
