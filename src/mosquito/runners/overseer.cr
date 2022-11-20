module Mosquito
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

      Log.info { "Worker [#{coordinator.instance_id}] reporting for duty" }

      @queues = [] of Queue
      @keep_running = true
    end

    # Infinite loop
    def run
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
    end
  end
end
