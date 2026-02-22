module Mosquito::Runners
  # primer? loader? _scheduler_
  class Coordinator
    Log = ::Log.for self
    LockTTL = 30.seconds

    getter lock_key : String
    getter instance_id : String
    getter queue_list : QueueList
    getter? is_leader : Bool = false

    def initialize(@queue_list)
      @lock_key = Backend.build_key :coordinator, :football
      @instance_id = Random::Secure.hex(8)
    end

    def runnable_name : String
      "coordinator.#{object_id}"
    end

    def schedule : Nil
      only_if_coordinator do
        enqueue_periodic_jobs
        enqueue_delayed_jobs
      end
    end

    def only_if_coordinator : Nil
      unless Mosquito.configuration.use_distributed_lock
        yield
        return
      end

      maintain_leadership

      if is_leader?
        yield
      end
    end

    # Releases the coordinator lease. Call during shutdown so another
    # instance can take over immediately instead of waiting for the
    # TTL to expire.
    def release_leadership : Nil
      return unless @is_leader
      Mosquito.backend.unlock lock_key, instance_id
      @is_leader = false
      Log.info { "Coordinator lease released" }
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

    private def maintain_leadership : Nil
      if @is_leader
        unless Mosquito.backend.renew_lock? lock_key, instance_id, LockTTL
          Log.info { "Lost coordinator lease" }
          @is_leader = false
          try_acquire
        end
      else
        try_acquire
      end
    end

    private def try_acquire : Nil
      if Mosquito.backend.lock? lock_key, instance_id, LockTTL
        Log.info { "Coordinator lease acquired" }
        @is_leader = true
      end
    end
  end
end
