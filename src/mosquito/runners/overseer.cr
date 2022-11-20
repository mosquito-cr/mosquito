module Mosquito::Runners
  # The Overseer is responsible for looking managing:
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

      @queues = [] of Queue
      @keep_running = true
    end

    private def worker_id
      "Worker [#{coordinator.instance_id}]"
    end

    def stop
      Log.info { worker_id + " willn't take any more work" }
      @keep_running = false
    end

    # Infinite loop
    def run
      Log.info { worker_id + " taking action" }

      while keep_running
        delta = Time.measure do
          queue_list.fetch
          coordinator.bloop
          executor.dequeue_and_run_jobs
        end

        if delta < idle_wait
          sleep(idle_wait - delta)
        end
      end

      Log.info { worker_id + " finished" }
    end
  end
end
