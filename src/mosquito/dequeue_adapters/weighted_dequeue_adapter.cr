require "../dequeue_adapter"

module Mosquito
  # A dequeue adapter that checks queues according to configured weights.
  #
  # Higher-weight queues are given proportionally more chances to be dequeued
  # from. On each call to `#dequeue`, the adapter picks a queue at random
  # (weighted by its configured value). If that queue is empty, it is removed
  # from consideration and another weighted pick is made, ensuring each queue
  # is checked at most once per dequeue call.
  #
  # The weight map is built fresh on each dequeue call from the current
  # queue list, ensuring newly discovered queues are picked up immediately.
  #
  # Queues not present in the weights table are assigned a default weight of 1.
  #
  # ## Example
  #
  # ```crystal
  # Mosquito.configure do |settings|
  #   settings.dequeue_adapter = Mosquito::WeightedDequeueAdapter.new({
  #     "critical" => 5,
  #     "default"  => 2,
  #     "bulk"     => 1,
  #   })
  # end
  # ```
  #
  # In this configuration the "critical" queue will be checked roughly 5x as
  # often as "bulk" and 2.5x as often as "default".
  class WeightedDequeueAdapter < DequeueAdapter
    getter weights : Hash(String, Int32)

    def initialize(@weights : Hash(String, Int32), @default_weight = 1)
    end

    def dequeue(queue_list : Runners::QueueList) : Tuple(JobRun, Queue)?
      remaining = queue_list.queues.map { |q|
        {q, weights.fetch(q.name, @default_weight)}
      }

      until remaining.empty?
        queue, index = weighted_random_select(remaining)
        if job_run = queue.dequeue
          return {job_run, queue}
        end
        remaining.delete_at(index)
      end
    end

    # Picks a queue at random, weighted by the associated values.
    # Returns the selected queue and its index in the candidates array.
    private def weighted_random_select(candidates : Array(Tuple(Queue, Int32))) : Tuple(Queue, Int32)
      total = candidates.sum(&.last)
      roll = rand(total)

      candidates.each_with_index do |(queue, weight), index|
        roll -= weight
        return {queue, index} if roll < 0
      end

      # Unreachable, but satisfies the compiler.
      {candidates.last.first, candidates.size - 1}
    end
  end
end
