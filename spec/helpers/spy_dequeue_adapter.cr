# A test adapter that tracks which queues were checked, in order.
class SpyDequeueAdapter < Mosquito::DequeueAdapter
  getter checked_queues = [] of String

  def dequeue(queue_list : Mosquito::Runners::QueueList) : Mosquito::WorkUnit?
    queue_list.queues.each do |q|
      @checked_queues << q.name
      if job_run = q.dequeue
        return Mosquito::WorkUnit.of(job_run, from: q)
      end
    end
  end
end
