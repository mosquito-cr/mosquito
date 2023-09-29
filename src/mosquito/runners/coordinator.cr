module Mosquito::Runners
  # primer? loader?
  class Coordinator
    include RunAtMost

    Log = ::Log.for self
    LockTTL = 10.seconds

    getter lock_key : String
    getter instance_id : String
    getter queue_list : QueueList

    def initialize(@queue_list)
      @lock_key = Backend.build_key :coordinator, :football
      @instance_id = Random::Secure.hex(8)

      @emitted_scheduling_deprecation_runtime_message = false
    end

    def bloop
      only_if_coordinator do
        enqueue_periodic_jobs
        enqueue_delayed_jobs
      end
    end

    def only_if_coordinator : Nil
      duration = 0.seconds

      if Mosquito.configuration.run_cron_scheduler
        yield

        unless @emitted_scheduling_deprecation_runtime_message
          Log.warn { "Scheduling coordinator / CRON Scheduler has been manually activated. This behavior is deprecated in favor of distributed locking and the default will change in 1.1.0. See https://github.com/mosquito-cr/mosquito/pull/108 " }
          @emitted_scheduling_deprecation_runtime_message = true
        end

        return
      end

      unless Mosquito.configuration.use_distributed_lock
        return
      end

      if Mosquito.backend.lock? lock_key, instance_id, LockTTL
        duration = Time.measure do
          yield
        end

        Mosquito.backend.unlock lock_key, instance_id
      end

      return unless duration > LockTTL
      Log.warn { "Coordination activities took longer than LockTTL (#{duration} > #{LockTTL}) " }
    end

    def enqueue_periodic_jobs
      run_at_most every: 1.second, label: :enqueue_periodic_job_runs do |now|
        Base.scheduled_job_runs.each do |scheduled_job_run|
          enqueued = scheduled_job_run.try_to_execute

          Log.for("enqueue_periodic_jobs").debug {
            "enqueued #{scheduled_job_run.class}" if enqueued
          }
        end
      end
    end

    def enqueue_delayed_jobs
      run_at_most every: 1.second, label: :enqueue_delayed_job_runs do |t|
        queue_list.each do |q|
          overdue_jobs = q.dequeue_scheduled
          next unless overdue_jobs.any?
          Log.for("enqueue_delayed_jobs").info { "#{overdue_jobs.size} delayed jobs ready in #{q.name}" }

          overdue_jobs.each do |job_run|
            q.enqueue job_run
          end
        end
      end
    end

  end
end
