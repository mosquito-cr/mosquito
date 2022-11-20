module Mosquito
  # overseer? arbiter? coordinator?
  class Bacon < Runners::Base
    Log = ::Log.for self

    # Minimum time in seconds to wait between checking for jobs.
    property idle_wait : Time::Span {
      Mosquito.configuration.idle_wait
    }

    getter queue_list, executor, coordinator

    def initialize
      @queue_list = QueueList.new
      @coordinator = Coordinator.new queue_list
      @executor = Executor.new queue_list

      Log.info { "Worker [#{coordinator.instance_id}] reporting for duty" }

      @queues = [] of Queue
    end

    def run
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
