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

    # When an executor transitions to idle it will send a True here. The Overseer
    # uses this as a signal to check the queues for more work.
    getter idle_notifier

    # The number of executors to start.
    getter executor_count : Int32 {
      Mosquito.configuration.executor_count
    }

    getter idle_wait : Time::Span {
      Mosquito.configuration.idle_wait
    }

    def initialize
      @idle_notifier = Channel(Bool).new

      @queue_list = QueueList.new
      @coordinator = Coordinator.new queue_list
      @dequeue_adapter = Mosquito.configuration.dequeue_adapter
      @executors = [] of Executor
      @work_handout = Channel(Tuple(JobRun, Queue)).new

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

    def stop(wait_group : WaitGroup? = nil) : Nil
      observer.shutting_down if state.running?
      super
    end

    # Notify all subprocesses to stop, and wait until they do.
    # After executors finish, any jobs left in the pending queue are
    # moved back to waiting so another worker can pick them up.
    def post_run : Nil
      observer.stopping

      wg = WaitGroup.new(executors.size + 1)
      executors.each { |e| e.stop(wg) }
      @queue_list.stop(wg)

      work_handout.close
      wg.wait
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
      if work_handout.closed? || idle_notifier.closed?
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
      when @idle_notifier.receive
        log.trace { "Found an idle executor" }
        all_executors_busy = false
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
        job_run, queue = next_job_run
        log.trace { "Dequeued job: #{job_run.id} #{queue.name}" }
        work_handout.send next_job_run

      # An executor is idle, but dequeue returned nil.
      else
        log.trace { "No job to dequeue" }
        sleep

        # The idle notification has been consumed, and it needs to be
        # re-sent so that the next loop can still find the idle executor.
        spawn { @idle_notifier.send true }
      end

      check_for_deceased_runners

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
    def dequeue_job? : Tuple(JobRun, Queue)?
      if result = dequeue_adapter.dequeue(queue_list)
        job_run, _queue = result
        job_run.claimed_by self
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
    def check_for_deceased_runners : Nil
      executors.select {|executor| executor.dead? || executor.state.crashed? }
        .each do |dead_executor|
          observer.executor_died dead_executor
          recover_job_from dead_executor
          executors.delete dead_executor
        end

      (executor_count - executors.size).times do
        executors << build_executor.tap(&.run)
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
        q.backend.dump_pending_q.each do |job_run_id|
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
          job_run.retry_or_banish q
          total += 1
        end
      end

      if total > 0
        observer.orphaned_jobs_recovered total
      end
    end

    # If a dead executor was working on a job, increment its failure
    # counter and follow the standard retry logic.
    private def recover_job_from(dead_executor : Executor) : Nil
      return unless job_run = dead_executor.job_run?

      observer.recovered_job_from_executor job_run, dead_executor
      job_run.retry_or_banish dead_executor.queue
    end

  end
end
