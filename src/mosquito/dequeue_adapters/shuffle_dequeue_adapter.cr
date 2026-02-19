require "../dequeue_adapter"

module Mosquito
  # The default dequeue adapter. Shuffles the queue list on each pass and
  # returns the first available job.
  #
  # The shuffle provides rough fairness across queues, preventing any single
  # queue from being consistently checked first.
  class ShuffleDequeueAdapter < DequeueAdapter
    def dequeue(queue_list : Runners::QueueList) : Tuple(JobRun, Queue)?
      queue_list.queues.shuffle.each do |q|
        if job_run = q.dequeue
          return {job_run, q}
        end
      end
    end
  end
end
