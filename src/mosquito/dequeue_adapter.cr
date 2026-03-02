module Mosquito
  # A DequeueAdapter determines how the Overseer selects the next job to
  # execute from the available queues.
  #
  # Subclass `DequeueAdapter`, implement `#dequeue`, and assign an instance
  # via `Mosquito.configure`:
  #
  # ```crystal
  # class MyDequeueAdapter < Mosquito::DequeueAdapter
  #   def dequeue(queue_list : Mosquito::Runners::QueueList) : Mosquito::WorkUnit?
  #     queue_list.queues.each do |q|
  #       if job_run = q.dequeue
  #         return WorkUnit.of(job_run, from: q)
  #       end
  #     end
  #   end
  # end
  #
  # Mosquito.configure do |settings|
  #   settings.dequeue_adapter = MyDequeueAdapter.new
  # end
  # ```
  abstract class DequeueAdapter
    # Attempt to dequeue a job from one of the queues managed by `queue_list`.
    #
    # Returns a `WorkUnit` when a job is available, or `nil`
    # when all queues are empty.
    abstract def dequeue(queue_list : Runners::QueueList) : WorkUnit?
  end
end
