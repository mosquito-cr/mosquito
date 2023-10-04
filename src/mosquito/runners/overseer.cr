module Mosquito::Runners
  # The Overseer is responsible for managing:
  # - a `Coordinator`
  # - an `Executor`
  # - the `QueueList`
  # - any idle state as configured
  #
  # An overseer manages the loop that each thread or process runs.
  class Overseer
    include RunAtMost

    Log = ::Log.for self

    # Minimum time in seconds to wait between checking for jobs.
    property idle_wait : Time::Span {
      Mosquito.configuration.idle_wait
    }

    property keep_running : Bool

    getter queue_list, executor, coordinator

    def initialize
      @queue_list = QueueList.new
      @coordinator = Coordinator.new queue_list
      @executor = Executor.new queue_list

      @keep_running = true
    end

    def worker_id
      "Worker [#{coordinator.instance_id}]"
    end

    def stop
      Log.info { worker_id + " is done after this job." }
      @keep_running = false
    end

    # Runs the overseer workflow.
    # Infinite loop.
    def run
      Log.info { worker_id + " clocking in." }

      while keep_running
        tick
      end

      Log.info { worker_id + " finished for now." }
    end

    def tick
      delta = Time.measure do
        queue_list.fetch
        run_at_most every: 1.second, label: :coordinator do
          coordinator.bloop
        end
        executor.dequeue_and_run_jobs
      end

      if delta < idle_wait
        sleep(idle_wait - delta)
      end
    end
  end
end
