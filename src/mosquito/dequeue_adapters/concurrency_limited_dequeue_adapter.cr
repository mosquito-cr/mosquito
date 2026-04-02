require "../dequeue_adapter"

module Mosquito
  # A dequeue adapter that enforces per-queue concurrency limits.
  #
  # Each queue can be assigned a maximum number of jobs that may execute
  # concurrently. When a queue has reached its limit, it is skipped during
  # dequeue until an in-flight job finishes.
  #
  # Queues not present in the limits table have no concurrency ceiling and
  # are bounded only by the total executor pool size.
  #
  # Among eligible queues the adapter uses a shuffle to provide rough
  # fairness, similar to `ShuffleDequeueAdapter`.
  #
  # ## Example
  #
  # ```crystal
  # Mosquito.configure do |settings|
  #   settings.executor_count = 8
  #
  #   settings.dequeue_adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
  #     "queue_a" => 3,
  #     "queue_b" => 5,
  #   })
  # end
  # ```
  #
  # In this configuration at most 3 jobs from "queue_a" and 5 from "queue_b"
  # will execute at the same time. Other queues are unlimited.
  class ConcurrencyLimitedDequeueAdapter < DequeueAdapter
    property limits : Hash(String, Int32)

    # Tracks the number of currently in-flight jobs per queue name.
    # Access is fiber-safe because Crystal fibers are cooperatively
    # scheduled and we never yield between read and write.
    @active : Hash(String, Int32)

    def initialize(@limits : Hash(String, Int32))
      @active = Hash(String, Int32).new(0)
    end

    def dequeue(queue_list : Runners::QueueList) : WorkUnit?
      queue_list.queues.shuffle.each do |q|
        if limit = limits[q.name]?
          next if @active[q.name] >= limit
        end

        if job_run = q.dequeue
          @active[q.name] = @active[q.name] + 1
          return WorkUnit.of(job_run, from: q)
        end
      end
    end

    # Called by the Overseer when a job from this queue has finished
    # executing. Decrements the in-flight counter so the queue becomes
    # eligible for dequeue again.
    def finished_with(job_run : JobRun, queue : Queue) : Nil
      count = @active[queue.name]
      @active[queue.name] = {count - 1, 0}.max
    end

    # Returns the current number of in-flight jobs for the given queue.
    def active_count(queue_name : String) : Int32
      @active[queue_name]
    end
  end
end
