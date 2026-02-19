# A test adapter that tracks which queues were checked, in order.
class SpyDequeueAdapter < Mosquito::DequeueAdapter
  getter checked_queues = [] of String

  def dequeue(queue_list : Mosquito::Runners::QueueList) : Tuple(Mosquito::JobRun, Mosquito::Queue)?
    queue_list.queues.each do |q|
      @checked_queues << q.name
      if job_run = q.dequeue
        return {job_run, q}
      end
    end
  end
end
