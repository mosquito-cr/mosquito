# A test adapter that always returns nil, simulating empty queues.
class NullDequeueAdapter < Mosquito::DequeueAdapter
  getter dequeue_count = 0

  def dequeue(queue_list : Mosquito::Runners::QueueList) : Tuple(Mosquito::JobRun, Mosquito::Queue)?
    @dequeue_count += 1
    nil
  end
end
