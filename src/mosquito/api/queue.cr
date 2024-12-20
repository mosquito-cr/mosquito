module Mosquito
  class Api::Queue
    getter name : String

    private property backend : Mosquito::Backend

    def self.all : Array(Queue)
      Mosquito.backend.list_queues.map { |name| new name }
    end

    def initialize(@name)
      @backend = Mosquito.backend.named name
    end

    {% for name in Mosquito::Backend::QUEUES %}
      def {{name.id}}_job_runs : Array(JobRun)
        backend.dump_{{name.id}}_q
          .map { |task_id| JobRun.new task_id }
      end
    {% end %}

    def size : Int64
      backend.size(include_dead: false)
    end

    def size_details : Hash(String, Int64)
      sizes = {} of String => Int64
      {% for name in Mosquito::Backend::QUEUES %}
        sizes["{{name.id}}"] = backend.{{name.id}}_size
      {% end %}
      sizes
    end

    def <=>(other)
      name <=> other.name
    end
  end

  class Observability::Queue
    include Publisher
    include Counter

    getter name : String

    def initialize(@queue : Mosquito::Queue)
      @name = queue.name
      @publish_context = PublishContext.new [:queue, queue.name]
    end

    def enqueued(job_run : JobRun) : Nil
      @queue.log.trace { "Enqueuing #{job_run} for immediate execution" }
      publish({title: "enqueue-job", job_run: job_run.id})
    end

    def enqueued(job_run : JobRun, at execute_time : Time) : Nil
      @queue.log.trace { "Enqueuing #{job_run} at #{execute_time}" }
      publish({title: "delay-job", job_run: job_run.id})
    end

    def dequeued(job_run : JobRun) : Nil
      @queue.log.trace { "Dequeuing #{job_run} for execution" }
      publish({title: "dequeue", job_run: job_run.id})
    end

    def rescheduled(job_run : Mosquito::JobRun, at execute_time : Time) : Nil
      @queue.log.trace { "Rescheduling #{job_run} for later execution at #{execute_time}" }
      publish({title: "reschedule", job_run: job_run.id})
    end

    def forgotten(job_run : JobRun)
      @queue.log.trace { "Forgetting #{job_run}" }
      publish({title: "forget", job_run: job_run.id})
    end

    def banished(job_run : JobRun)
      @queue.log.trace { "Banishing #{job_run}" }
      publish({title: "banish", job_run: job_run.id})
    end
  end
end
