module Mosquito::Inspector
  class Queue
    getter name : String

    private property backend : Mosquito::Backend

    def initialize(@name)
      @backend = Mosquito.backend.named name
    end

    {% for name in Mosquito::Backend::QUEUES %}
      def {{name.id}}_job_runs : Array(JobRun)
        backend.dump_{{name.id}}_q
          .map { |task_id| JobRun.new task_id }
      end

      def {{name.id}}_size : Int64
        backend.{{name.id}}_size
      end
    {% end %}

    def sizes : Hash(String, Int64)
      sizes = {} of String => Int64
      {% for name in Mosquito::Backend::QUEUES %}
        sizes["{{name.id}}"] = {{name.id}}_size
      {% end %}
      sizes
    end

    def <=>(other)
      name <=> other.name
    end
  end
end
