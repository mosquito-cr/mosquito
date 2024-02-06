require "uuid"

require "../runnable"

require "./concerns/*"
require "./coordinator"
require "./executor"
require "./queue_list"

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
    include Identifiable

    Log = ::Log.for self

    getter queue_list : QueueList {
      QueueList.new self
    }

    getter executors : Array(Executor) = [] of Executor

    getter coordinator : Coordinator {
      Coordinator.new self, queue_list
    }

    getter observer : Observability::Overseer { Observability::Overseer.new(self) }

    # The channel where job runs which have been dequeued are sent to executors.
    getter work_handout : Channel(Tuple(JobRun, Queue))

    # When an executor transitions to idle it will send a True here. The Overseer
    # uses this as a signal to check the queues for more work.
    getter idle_notifier : Channel(Bool)

    # The number of executors to start.
    getter executor_count = 8

    getter idle_wait : Time::Span {
      Mosquito.configuration.idle_wait
    }

    property state : State = State::Starting

    def initialize
      @idle_notifier = Channel(Bool).new

      @work_handout = Channel(Tuple(JobRun, Queue)).new

      executor_count.times do
        @executors << build_executor
      end

      observer.update_executor_list
    end

    def build_executor : Executor
      Executor.new self
    end

    def runnable_name : String
      "Overseer<#{@instance_id}>"
    end

    def sleep
      Log.trace { "Going to sleep now for #{idle_wait}" }
      sleep idle_wait
    end

    # Starts all the subprocesses.
    def pre_run : Nil
      observer.starting
      queue_list.run
      @executors.each(&.run)
    end

    # Notify all subprocesses to stop, and wait until they do.
    def post_run : Nil
      observer.stopping
      stopped_notifiers = executors.map do |executor|
        executor.stop
      end
      work_handout.close
      stopped_notifiers.each(&.receive)
      observer.stopped
    end

    # The goal for the overseer is to:
    # - Ensure that the coordinator gets run frequently to schedule delayed/periodic jobs.
    # - Wait for an executor to be idle, and dequeue work if possible.
    # - Monitor the executor pool for unexpected termination and respawn.
    def each_run : Nil
      coordinator.schedule

      # I cannot imagine a situation where this happens in the normal flow of
      # events, but if it did it would be a mess. If something crashes hard
      # enough that one of these channels closes the whole thing is going to
      # come crashing down and we should just quit now.
      if work_handout.closed? || idle_notifier.closed?
        observer.will_stop "Executor communication channels closed."
        stop
        return
      end

      # If the queue list hasn't run at least once, it won't have any queues to
      # search for so we'll just defer until it's available.
      unless queue_list.state.started?
        Log.trace { "Waiting for the queue list to fetch possible queues" }
        return
      end

      Log.trace { "Waiting for an idle executor" }
      all_executors_busy = true

      # This feature is under documented in the crystal manual.
      # This will attempt to receive from a the idle notifier, but only
      # wait for up to idle_wait seconds.
      #
      # The interrupt is necessary to remind the coordinator to schedule
      # jobs.
      select
      when @idle_notifier.receive
        Log.trace { "Found an idle executor" }
        all_executors_busy = false
      when timeout(idle_wait)
      end

      case
      # If none of the executors is idle, don't dequeue anything or it'll get lost.
      when all_executors_busy
        Log.trace { "No idle executors" }

      # We know that an executor is idle and will take the work, it's safe to dequeue.
      when next_job_run = dequeue_job?
        job_run, queue = next_job_run
        Log.trace { "Dequeued job: #{job_run.id} #{queue.name}" }
        work_handout.send next_job_run

      # An executor is idle, but dequeue returned nil.
      else
        Log.trace { "No job to dequeue" }
        sleep

        # The idle notification has been consumed, and it needs to be
        # re-sent so that the next loop can still find the idle executor.
        spawn { @idle_notifier.send true }
      end

      check_for_deceased_runners
      run_at_most every: Mosquito.configuration.heartbeat_interval, label: :heartbeat do
        observer.heartbeat
      end
    end

    # Weaknesses: This implementation sometimes starves queues because it doesn't
    # round robin, prioritize queues, or anything else.
    def dequeue_job? : Tuple(JobRun, Queue)?
      queue_list.each do |q|
        if job_run = q.dequeue
          return { job_run, q }
        end
      end
    end

    # If an executor dies, it's probably because a bug exists somewhere in Mosquito itself.
    #
    # When a job fails any exceptions are caught and logged. If a job causes something more
    # catastrophic we can try to recover by spawning a new executor.
    def check_for_deceased_runners : Nil
      executors.select{|e| e.state.started?}.select(&.dead?).each do |dead_executor|
        observer.executor_died dead_executor
        executors.delete dead_executor
      end

      (executor_count - executors.size).times do
        executors << build_executor.tap(&.run)
      end

      observer.update_executor_list

      if queue_list.dead?
        observer.will_stop("QueueList has died.")
        stop
      end
    end
  end
end
