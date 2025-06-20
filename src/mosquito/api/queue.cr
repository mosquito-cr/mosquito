module Mosquito
  # Represents a named queue in the system, and allows querying the state of the queue. For more about the internals of a Queue in Mosquito, see `Mosquito::Queue`.
  class Api::Queue
    # The name of the queue.
    getter name : String

    private property backend : Mosquito::Backend

    # Returns a list of all known named queues in the system.
    def self.all : Array(Queue)
      Mosquito.backend.list_queues.map { |name| new name }
    end

    # Creates an instance of a named queue.
    def initialize(@name : String)
      @backend = Mosquito.backend.named name
    end

    {% for name in Mosquito::Backend::QUEUES %}
      # Gets a list of all the job runs in the internal {{name.id}} queue.
      def {{name.id}}_job_runs : Array(JobRun)
        backend.dump_{{name.id}}_q
          .map { |task_id| JobRun.new task_id }
      end
    {% end %}

    # The operating size of the queue, not including dead jobs.
    def size : Int64
      backend.size(include_dead: false)
    end

    # The total size of the queue, including all states.
    def total_size : Int64
      backend.size(include_dead: true)
    end

    # Individual queue state sizes
    {% for name in Mosquito::Backend::QUEUES %}
      def {{name.id}}_size : Int64
        backend.{{name.id}}_size
      end
    {% end %}

    # The size of the queue, broken out by job state.
    #
    # Example:
    #
    # ```
    # Mosquito::Api::Queue.all.first.size_details
    # # => {"waiting" => 0, "scheduled" => 0, "pending" => 0, "dead" => 0}
    # ```
    #
    # The semantics of the keys are described in detail on the `Mosquito::Queue` class, but in brief:
    #
    # - `scheduled` is a list of jobs which are scheduled to be executed at a later time.
    # - `waiting` is a list of jobs which should be executed ASAP
    # - `pending` is a list of jobs for which execution has started
    # - `dead` is a list of jobs which have failed to execute
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
      data = {event: "enqueued", job_run: job_run.id}
      publish(data)
      track_metrics(data)
    end

    def enqueued(job_run : JobRun, at execute_time : Time)
      log.trace { "Enqueuing #{job_run.id} for execution at #{execute_time}" }
      data = {event: "enqueued", job_run: job_run.id, execute_time: execute_time}
      publish(data)
      track_metrics(data)
    end

    def dequeued(job_run : JobRun)
      log.trace { "Dequeuing #{job_run.id}" }
      data = {event: "dequeued", job_run: job_run.id}
      publish(data)
      track_metrics(data)
    end
  end
end
