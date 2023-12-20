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

    Log = ::Log.for self

    getter queue_list : QueueList
    getter executors
    getter coordinator

    # The channel where job runs which have been dequeued are sent to executors.
    getter work_handout

    # When an executor transitions to idle it will send a True here. The Overseer
    # uses this as a signal to check the queues for more work.
    getter idle_notifier

    # The number of executors to start.
    getter executor_count = 3

    getter idle_wait : Time::Span {
      Mosquito.configuration.idle_wait
    }

    def initialize
      @idle_notifier = Channel(Bool).new

      @queue_list = QueueList.new
      @coordinator = Coordinator.new queue_list
      @executors = [] of Executor
      @work_handout = Channel(Tuple(JobRun, Queue)).new

      executor_count.times do
        @executors << build_executor
      end
    end

    def build_executor : Executor
      Executor.new(work_handout, idle_notifier)
    end

    def runnable_name : String
      "Overseer<#{object_id}>"
    end

    def sleep
      Log.trace { "Going to sleep now for #{idle_wait}" }
      sleep idle_wait
    end

    # Starts all the subprocesses.
    def pre_run : Nil
      Log.info { "Starting #{@executors.size} executors." }
      @queue_list.run
      @executors.each(&.run)
    end

    # Notify all subprocesses to stop, and wait until they do.
    def post_run : Nil
      Log.info { "Stopping #{@executors.size} executors." }
      stopped_notifiers = executors.map do |executor|
        executor.stop
      end
      work_handout.close
      stopped_notifiers.each(&.receive)
      Log.info { "All executors stopped." }
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
        Log.fatal { "Executor communication channels closed, overseer will stop." }
        stop
        return
      end

      # If the queue list hasn't run at least once, it won't have any queues to
      # search for so we'll just defer until it's available.
      unless queue_list.state.started?
        Log.debug { "Waiting for the queue list to fetch possible queues" }
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
        Log.fatal do
          <<-MSG
            Executor #{dead_executor.runnable_name} died.
            A new executor will be started.
          MSG
        end
        executors.delete dead_executor
      end

      (executor_count - executors.size).times do
        executors << build_executor.tap(&.run)
      end

      if queue_list.dead?
        Log.fatal { "QueueList has died, overseer will stop." }
        stop
      end
    end
  end
end
