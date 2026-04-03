module Mosquito::Runners
  # A dedicated runner that periodically polls registered PerpetualJob
  # classes by calling `next_batch` on a fresh instance and enqueuing
  # the results.
  #
  # This runner is driven by the Overseer (called each tick, like the
  # Coordinator) and only runs when the Coordinator holds the leadership
  # lock, avoiding duplicate polling across processes.
  class PerpetualJobRunner
    Log = ::Log.for self

    getter coordinator : Coordinator

    def initialize(@coordinator)
    end

    # Called each tick by the Overseer.  Polls registered perpetual
    # jobs when this process is the coordinator leader.
    def poll : Nil
      coordinator.only_if_coordinator do
        enqueue_perpetual_jobs
      end
    end

    private def enqueue_perpetual_jobs
      Base.perpetual_job_runs.each do |perpetual_job_run|
        perpetual_job_run.try_to_poll
      end
    end
  end
end
