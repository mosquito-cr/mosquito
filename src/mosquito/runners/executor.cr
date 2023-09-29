module Mosquito::Runners
  # An Executor is responsible for building Job classes with deserialized
  # parameters and calling #run on them. It measures the time it takes to
  # run a job and provides detailed log messages about the current status.
  #
  # Executor#deqeue_and_run_jobs is the entrypoint and shoud be treated as
  # if it will return only after a relative eternity.
  class Executor
    include RunAtMost

    Log = ::Log.for self

    # How long a job config is persisted after success
    property successful_job_ttl : Int32 { Mosquito.configuration.successful_job_ttl }

    # How long a job config is persisted after failure
    property failed_job_ttl : Int32 { Mosquito.configuration.failed_job_ttl }

    getter queue_list : QueueList

    def initialize(@queue_list)
    end

    def dequeue_and_run_jobs
      queue_list.each do |q|
        run_next_job q
      end
    end

    def run_next_job(q : Queue)
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
        message = String::Builder.new
        message << "Failure: ".colorize.red
        message << job_run
        message << " failed, taking "
        message << time_with_units duration
        message << " and "

        if job_run.rescheduleable?
          next_execution = Time.utc + job_run.reschedule_interval
          q.reschedule job_run, next_execution

          message << "will run again".colorize.cyan
          message << " in "
          message << job_run.reschedule_interval
          message << " (at "
          message << next_execution
          message << ")"
        else
          q.banish job_run
          job_run.delete in: failed_job_ttl

          message << "cannot be rescheduled".colorize.yellow
        end

        Log.warn { message.to_s }
      end
    end

    def time_with_units(seconds : Float64)
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
