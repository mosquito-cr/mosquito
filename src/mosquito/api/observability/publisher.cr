module Mosquito::Observability::Publisher
  getter publish_context : PublishContext

  macro metrics(&block)
    if Mosquito.configuration.metrics?
      {{ block.body }}
    end
  end

  @[AlwaysInline]
  def publish(data : NamedTuple)
    metrics do
      Log.debug { "Publishing #{data} to #{@publish_context.originator}" }
      Mosquito.backend.publish(
        publish_context.originator,
        data.to_json
      )
    end
  end

  @[AlwaysInline]
  def track_metrics(data : NamedTuple)
    metrics do
      # Track metrics based on the event type
      case data[:event]?
      when "enqueued"
        if job_run_id = data[:job_run]?.try(&.as(String))
          track_enqueue_metrics(job_run_id)
        end
      when "job-started"
        if (job_run_id = data[:job_run]?.try(&.as(String))) && (queue_name = data[:from_queue]?.try(&.as(String)))
          track_start_metrics(job_run_id, queue_name)
        end
      when "job-finished"
        if job_run_id = data[:job_run]?.try(&.as(String))
          track_finish_metrics(job_run_id)
        end
      end
    end
  end

  private def track_enqueue_metrics(job_run_id : String)
    job_run = Api::JobRun.new(job_run_id)
    return unless job_run.found?

    queue_name = job_run.queue_name || "default"
    job_type = job_run.type
    Api::Metrics.increment_enqueued(queue_name, job_type)
  end

  private def track_start_metrics(job_run_id : String, queue_name : String)
    job_run = Api::JobRun.new(job_run_id)
    return unless job_run.found?

    job_type = job_run.type
    Api::Metrics.increment_started(queue_name, job_type)
  end

  private def track_finish_metrics(job_run_id : String)
    job_run = Api::JobRun.new(job_run_id)
    return unless job_run.found?

    queue_name = job_run.queue_name || "default"
    job_type = job_run.type

    if job_run.successful?
      duration_ms = job_run.duration.try(&.total_milliseconds.to_i64) || 0_i64
      Api::Metrics.increment_finished(queue_name, job_type, duration_ms)
    else
      Api::Metrics.increment_failed(queue_name, job_type)
    end
  end

  class PublishContext
    alias Context = Array(String | Symbol | UInt64)
    property originator : String
    property context : String

    def initialize(context : Context)
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", @context
    end

    def initialize(parent : self, context : Context)
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", parent.context, context
    end
  end
end
