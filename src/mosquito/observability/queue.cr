require "./concerns/*"

module Mosquito::Observability
  class Queue
    include Publisher
    include Counter

    private getter name : String

    def initialize(@queue : Mosquito::Queue)
      @name = queue.name
      @publish_context = PublishContext.new [:queue, queue.name]
    end

    def enqueued(job_run : Mosquito::JobRun) : Nil
      @queue.log.trace { "Enqueuing #{job_run} for immediate execution" }
      count [:queue, name, :enqueue]
      publish({title: "enqueue-job", job_run: job_run.id})
      #, depth: size}
    end

    def enqueued(job_run : Mosquito::JobRun, at execute_time : Time) : Nil
      @queue.log.trace { "Enqueuing #{job_run} for later execution at #{execute_time}" }
      count [:queue, name, :enqueue]
      publish({title: "delay-job", job_run: job_run.id})
      #, depth: size}
    end

    def dequeued(job_run : Mosquito::JobRun) : Nil
      @queue.log.trace { "Dequeuing #{job_run} for execution" }
      count [:queue, name, :dequeue]
      publish({title: "dequeue", job_run: job_run.id})
      #, depth: size}
    end

    def rescheduled(job_run : Mosquito::JobRun, at execute_time : Time) : Nil
      @queue.log.trace { "Rescheduling #{job_run} for later execution at #{execute_time}" }
      count [:queue, name, :reschedule]
      publish({title: "reschedule", job_run: job_run.id})
      #, depth: size}
    end

    def forgotten(job_run : Mosquito::JobRun) : Nil
      @queue.log.trace { "Forgetting #{job_run}" }
      count [:queue, name, :forget]
      publish({title: "forget", job_run: job_run.id})
      #, depth: size})
    end

    def banished(job_run : Mosquito::JobRun) : Nil
      @queue.log.trace { "Banishing #{job_run}" }
      count [:queue, name, :banish]
      publish({title: "banish", job_run: job_run.id})
      #, depth: size})
    end
  end
end
