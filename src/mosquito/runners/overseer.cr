require "./idle_wait"
require "./queue_list"
require "./run_at_most"
require "../runnable"

module Mosquito::Runners
  # The Overseer is responsible for managing:
  # - a `Coordinator`
  # - an `Executor`
  # - the `QueueList`
  # - any idle state as configured
  #
  # An overseer manages the loop that each thread or process runs.
  class Overseer
    include IdleWait
    include RunAtMost
    include Runnable

    getter observer : Observability::Overseer { Observability::Overseer.new(self) }

    getter queue_list : QueueList
    getter executors
    getter coordinator
    getter dequeue_adapter : Mosquito::DequeueAdapter

    # The channel where job runs which have been dequeued are sent to executors.
    getter work_handout

    # When an executor transitions to idle it will send the finished
    # {JobRun, Queue} tuple here (or nil on first idle). The Overseer
    # uses this as a signal to check the queues for more work.
    getter finished_notifier

    # The number of executors to start.
    getter executor_count : Int32

    def executor_count=(count : Int32)
      @executor_count = Math.max(count, 1)
    end

    getter idle_wait : Time::Span

    def initialize
      @executor_count = Mosquito.configuration.executor_count
      @idle_wait = Mosquito.configuration.idle_wait
      @finished_notifier = Channel(WorkUnit?).new

      @queue_list = QueueList.new
      @queue_list.resource_gates = Mosquito.configuration.resource_gates
      @coordinator = Coordinator.new queue_list
      @dequeue_adapter = Mosquito.configuration.dequeue_adapter
      @executors = [] of Executor
      @work_handout = Channel(WorkUnit).new

      executor_count.times do
        @executors << build_executor
      end

      observer.update_executor_list executors
    end

    def build_executor : Executor
      Executor.new(overseer: self).tap do |executor|
        observer.executor_created executor
      end
    end

    def runnable_name : String
      "overseer"
    end

    def sleep
      log.trace { "Going to sleep now for #{idle_wait}" }
      sleep idle_wait
    end

    # Starts all the subprocesses.
    def pre_run : Nil
      observer.starting
      @queue_list.run
      @executors.each(&.run)
    end

    def stop(wait_group : WaitGroup = WaitGroup.new(1)) : WaitGroup
      observer.shutting_down if state.running?
      super
    end

    # Notify all subprocesses to stop, and wait until they do.
    # After executors finish, any jobs left in the pending queue are
    # moved back to waiting so another worker can pick them up.
    def post_run : Nil
      observer.stopping

      coordinator.post_run

      child_fiber_shutdown = WaitGroup.new(executors.size + 1)
      executors.each { |e| e.stop(child_fiber_shutdown) }
      @queue_list.stop(child_fiber_shutdown)

      work_handout.close
      child_fiber_shutdown.wait
      observer.stopped
    end

    # The goal for the overseer is to:
    # - Ensure that the coordinator gets run frequently to schedule delayed/periodic jobs.
    # - Wait for an executor to be idle, and dequeue work if possible.
    # - Monitor the executor pool for unexpected termination and respawn.
    def each_run : Nil
      # When shutting down, stop dequeuing new work immediately.
      return if state.stopping?

      coordinator.schedule

      # I cannot imagine a situation where this happens in the normal flow of
      # events, but if it did it would be a mess. If something crashes hard
      # enough that one of these channels closes the whole thing is going to
      # come crashing down and we should just quit now.
      if work_handout.closed? || finished_notifier.closed?
        observer.channels_closed
        stop
        return
      end

      # If the queue list hasn't run at least once, it won't have any queues to
      # search for so we'll just defer until it's available.
      unless queue_list.state.started?
        observer.waiting_for_queue_list
        return
      end


      log.trace { "Waiting for an idle executor" }
      all_executors_busy = true

      # This feature is under documented in the crystal manual.
      # This will attempt to receive from a the idle notifier, but only
      # wait for up to idle_wait seconds.
      #
      # The interrupt is necessary to remind the coordinator to schedule
      # jobs.
      select
      when finished_job = @finished_notifier.receive
        log.trace { "Found an idle executor" }
        all_executors_busy = false
        if finished_job
          dequeue_adapter.finished_with(finished_job.job_run, finished_job.queue)
          queue_list.notify_released(finished_job.job_run, finished_job.queue)
        end
      when timeout(idle_wait)
        log.trace { "Idled for #{idle_wait.total_seconds}s" }
      end

      case
      when state.stopping?
      # If none of the executors is idle, don't dequeue anything or it'll get lost.
      when all_executors_busy
        log.trace { "No idle executors" }

      # We know that an executor is idle and will take the work, it's safe to dequeue.
      when next_job_run = dequeue_job?
        log.trace { "Dequeued job: #{next_job_run.job_run.id} #{next_job_run.queue.name}" }
        work_handout.send next_job_run

      # An executor is idle, but dequeue returned nil.
      else
        log.trace { "No job to dequeue" }
        sleep

        # The idle notification has been consumed, and it needs to be
        # re-sent so that the next loop can still find the idle executor.
        spawn { @finished_notifier.send nil }
      end

      maybe_apply_remote_executor_count

      adjust_executor_pool

      run_at_most every: Mosquito.configuration.heartbeat_interval, label: :heartbeat do
        observer.heartbeat
      end

      run_at_most every: Mosquito.configuration.heartbeat_interval * 3, label: :pending_cleanup do
        cleanup_orphaned_pending_jobs
      end
    end

    # Delegates job dequeue to the configured `DequeueAdapter`.
    #
    # The adapter can be swapped via `Mosquito.configuration.dequeue_adapter`
    # to implement custom strategies (priority, round-robin, rate limiting, etc).
    def dequeue_job? : WorkUnit?
      if result = dequeue_adapter.dequeue(queue_list)
        result.job_run.claimed_by self
      end
      result
    end

    # When a job fails any exceptions are caught and logged. If a job causes something more
    # catastrophic we can try to recover by spawning a new executor.
    #
    # This happens, for example, when a new version of a worker is deployed and work is still
    # in the queue that references job classes that no longer exist.
    #
    # When a dead executor is found, any job it was working on has its
    # failure counter incremented and follows the standard retry logic.
    def adjust_executor_pool : Nil
      # Remove dead/crashed executors and recover their jobs.
      executors.select {|executor| executor.dead? || executor.state.crashed? }
        .each do |dead_executor|
          observer.executor_died dead_executor
          recover_job_from dead_executor
          executors.delete dead_executor
        end

      # Scale up: spawn new executors to reach the target count.
      (executor_count - executors.size).times do
        executors << build_executor.tap(&.run)
      end

      # Scale down: decommission excess executors and remove them from the pool.
      # They will finish their current job (if any) and then stop.
      while executors.size > executor_count
        executors.pop.decommission!
      end

      observer.update_executor_list executors

      if queue_list.dead?
        observer.queue_list_died
        stop
      end
    end

    # Scans pending queues for jobs owned by overseers that are no longer
    # alive. Each orphaned job has its failure counter incremented and
    # follows the standard retry logic.
    #
    # An overseer is considered alive if it has registered a heartbeat
    # within the configured dead_overseer_threshold. Jobs with no overseer_id (pre-
    # dating this feature) are claimed by this overseer so they become
    # recoverable when this overseer later dies.
    # :nodoc:
    def cleanup_orphaned_pending_jobs : Nil
      live_overseers = Mosquito.backend.list_active_overseers(
        since: Time.utc - Mosquito.configuration.dead_overseer_threshold
      ).to_set

      queue_names = Mosquito.backend.list_queues
      return if queue_names.empty?

      total = 0
      queue_names.each do |name|
        q = Queue.new(name)
        q.backend.list_pending.each do |job_run_id|
          job_run = JobRun.retrieve(job_run_id)

          unless job_run
            # Job config is gone (expired/deleted), just clean up the
            # dangling reference in the pending queue.
            q.backend.finish JobRun.new("_cleanup", id: job_run_id)
            total += 1
            next
          end

          # Jobs without an overseer_id predate this feature. Claim them
          # so a future cleanup cycle can detect if this overseer dies.
          unless oid = job_run.overseer_id
            job_run.claimed_by self
            next
          end

          next if live_overseers.includes?(oid)

          observer.recovered_orphaned_job job_run, oid
          begin
            job_run.retry_or_banish q
          rescue e : KeyError
            log.warn { "Skipping orphaned job #{job_run_id}: #{e.message}" }
            q.banish job_run
          end
          total += 1
        end
      end

      if total > 0
        observer.orphaned_jobs_recovered total
      end
    end

    # Polls the backend for a remote executor count override and applies
    # it when present. Checks at most once per heartbeat interval.
    # The resolved value follows the precedence: per-overseer → global → current.
    private def maybe_apply_remote_executor_count : Nil
      run_at_most every: Mosquito.configuration.heartbeat_interval, label: :remote_executor_count do
        overseer_id = Mosquito.configuration.overseer_id
        if remote_count = Api::ExecutorConfig.resolve(overseer_id)
          clamped = Math.max(remote_count, 1)
          if clamped != executor_count
            log.info { "Remote executor count changed: #{executor_count} → #{clamped}" }
            self.executor_count = clamped
          end
        end
      rescue ex
        log.warn { "Failed to fetch remote executor count: #{ex.message}" }
      end
    end

    # If a dead executor was working on a job, increment its failure
    # counter and follow the standard retry logic.
    private def recover_job_from(dead_executor : Executor) : Nil
      return unless work_unit = dead_executor.work_unit?

      observer.recovered_job_from_executor work_unit.job_run, dead_executor
      dequeue_adapter.finished_with(work_unit.job_run, work_unit.queue)
      work_unit.job_run.retry_or_banish work_unit.queue
    end

  end
end
