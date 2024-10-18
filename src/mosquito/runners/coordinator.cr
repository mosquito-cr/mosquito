module Mosquito::Runners
  # primer? loader? _scheduler_
  class Coordinator
    Log = ::Log.for self
    LockTTL = 10.seconds

    getter lock_key : String
    getter instance_id : String
    getter queue_list : QueueList
    getter overseer : Overseer

    def initialize(@overseer, @queue_list)
      @lock_key = Backend.build_key :coordinator, :football
      @instance_id = Random::Secure.hex(8)
      # @publish_context = PublishContext.new(overseer_context, [:coordinator, instance_id])
    end

    def runnable_name : String
      "Coordinator<#{object_id}>"
    end

    def schedule : Nil
      only_if_coordinator do
        enqueue_periodic_jobs
        enqueue_delayed_jobs
      end
    end

    def only_if_coordinator : Nil
      duration = 0.seconds

      unless Mosquito.configuration.use_distributed_lock
        return
      end

      if Mosquito.backend.lock? lock_key, instance_id, LockTTL
        duration = Time.measure do
          overseer.observer.coordinating do
            yield
          end
        end

        Mosquito.backend.unlock lock_key, instance_id
      end

      return unless duration > LockTTL
      Log.warn { "Coordination activities took longer than LockTTL (#{duration} > #{LockTTL}) " }
    end

    def enqueue_periodic_jobs
      Base.scheduled_job_runs.each do |scheduled_job_run|
        enqueued = scheduled_job_run.try_to_execute
      end
    end

    def enqueue_delayed_jobs
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
