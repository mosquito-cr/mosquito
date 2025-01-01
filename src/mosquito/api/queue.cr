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

    getter log : ::Log
    getter publish_context : PublishContext

    def initialize(@queue : Mosquito::Queue)
      @publish_context = PublishContext.new [:queue, queue.name]
      @log = Log.for(queue.name)
    end

    def enqueued(job_run : JobRun)
      log.trace { "Enqueuing #{job_run.id} for immediate execution" }
      publish({event: "enqueued", job_run: job_run.id})
    end

    def enqueued(job_run : JobRun, at execute_time : Time)
      log.trace { "Enqueuing #{job_run.id} for execution at #{execute_time}" }
      publish({event: "enqueued", job_run: job_run.id, execute_time: execute_time})
    end

    def dequeued(job_run : JobRun)
      log.trace { "Dequeuing #{job_run.id}" }
      publish({event: "dequeued", job_run: job_run.id})
    end
  end
end
