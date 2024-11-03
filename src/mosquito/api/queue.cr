module Mosquito::Api
  class Queue
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
end
