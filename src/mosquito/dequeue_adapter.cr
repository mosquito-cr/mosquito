module Mosquito
  # A DequeueAdapter determines how the Overseer selects the next job to
  # execute from the available queues.
  #
  # Subclass `DequeueAdapter`, implement `#dequeue`, and assign an instance
  # via `Mosquito.configure`:
  #
  # ```crystal
  # class MyDequeueAdapter < Mosquito::DequeueAdapter
  #   def dequeue(queue_list : Mosquito::Runners::QueueList) : Tuple(Mosquito::JobRun, Mosquito::Queue)?
  #     queue_list.queues.each do |q|
  #       if job_run = q.dequeue
  #         return {job_run, q}
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
    # Returns a tuple of `{JobRun, Queue}` when a job is available, or `nil`
    # when all queues are empty.
    abstract def dequeue(queue_list : Runners::QueueList) : Tuple(JobRun, Queue)?
  end
end
