module Mosquito::Api
  # Handles metrics collection and retrieval for job performance analytics
  class Metrics
    METRICS_KEY_PREFIX = "metrics"

    def self.increment_enqueued(queue_name : String, job_type : String) : Nil
      increment_metric("enqueued:#{queue_name}:#{job_type}")
      increment_metric("enqueued:#{queue_name}:total")
      increment_metric("enqueued:total")
    end

    def self.increment_started(queue_name : String, job_type : String) : Nil
      increment_metric("started:#{queue_name}:#{job_type}")
      increment_metric("started:#{queue_name}:total")
      increment_metric("started:total")
    end

    def self.increment_finished(queue_name : String, job_type : String, duration_ms : Int64) : Nil
      increment_metric("finished:#{queue_name}:#{job_type}")
      increment_metric("finished:#{queue_name}:total")
      increment_metric("finished:total")

      # Track duration
      duration_key = "duration:#{queue_name}:#{job_type}"
      record_duration(duration_key, duration_ms)
    end

    def self.increment_failed(queue_name : String, job_type : String) : Nil
      increment_metric("failed:#{queue_name}:#{job_type}")
      increment_metric("failed:#{queue_name}:total")
      increment_metric("failed:total")
    end

    def self.get_enqueued_count(queue_name : String? = nil, job_type : String? = nil) : Int64
      key = if queue_name && job_type
              "enqueued:#{queue_name}:#{job_type}"
            elsif queue_name
              "enqueued:#{queue_name}:total"
            else
              "enqueued:total"
            end
      get_metric(key)
    end

    def self.get_finished_count(queue_name : String? = nil, job_type : String? = nil) : Int64
      key = if queue_name && job_type
              "finished:#{queue_name}:#{job_type}"
            elsif queue_name
              "finished:#{queue_name}:total"
            else
              "finished:total"
            end
      get_metric(key)
    end

    def self.get_failed_count(queue_name : String? = nil, job_type : String? = nil) : Int64
      key = if queue_name && job_type
              "failed:#{queue_name}:#{job_type}"
            elsif queue_name
              "failed:#{queue_name}:total"
            else
              "failed:total"
            end
      get_metric(key)
    end

    def self.get_success_rate(queue_name : String? = nil, job_type : String? = nil) : Float64
      finished = get_finished_count(queue_name, job_type)
      failed = get_failed_count(queue_name, job_type)
      total = finished + failed

      return 0.0 if total == 0
      (finished.to_f / total.to_f) * 100.0
    end

    def self.get_average_duration(queue_name : String, job_type : String) : Float64
      duration_key = "duration:#{queue_name}:#{job_type}"
      avg_key = build_metrics_key("#{duration_key}:avg")
      count_key = build_metrics_key("#{duration_key}:count")

      avg = Mosquito.backend.get(avg_key, "value").try(&.to_f) || 0.0
      count = Mosquito.backend.get(count_key, "value").try(&.to_i64) || 0_i64

      return 0.0 if count == 0
      avg
    end

    def self.get_throughput(queue_name : String? = nil, time_window : Time::Span = 1.hour) : Float64
      # This is a simplified throughput calculation
      # In a production system, you'd want to track this with time-based windows
      finished_count = get_finished_count(queue_name)
      window_hours = time_window.total_hours

      return 0.0 if window_hours == 0
      finished_count.to_f / window_hours
    end

    def self.queue_metrics(queue_name : String) : Hash(String, Float64 | Int64)
      {
        "enqueued_count"      => get_enqueued_count(queue_name),
        "finished_count"      => get_finished_count(queue_name),
        "failed_count"        => get_failed_count(queue_name),
        "success_rate"        => get_success_rate(queue_name),
        "throughput_per_hour" => get_throughput(queue_name),
      }
    end

    def self.job_type_metrics(queue_name : String, job_type : String) : Hash(String, Float64 | Int64)
      {
        "enqueued_count"      => get_enqueued_count(queue_name, job_type),
        "finished_count"      => get_finished_count(queue_name, job_type),
        "failed_count"        => get_failed_count(queue_name, job_type),
        "success_rate"        => get_success_rate(queue_name, job_type),
        "average_duration_ms" => get_average_duration(queue_name, job_type),
        "throughput_per_hour" => get_throughput(queue_name),
      }
    end

    def self.global_metrics : Hash(String, Float64 | Int64)
      {
        "total_enqueued"             => get_enqueued_count,
        "total_finished"             => get_finished_count,
        "total_failed"               => get_failed_count,
        "global_success_rate"        => get_success_rate,
        "global_throughput_per_hour" => get_throughput,
      }
    end

    def self.reset_metrics : Nil
      # This would reset all metrics - use with caution in production
      pattern = build_metrics_key("*")
      # This is a simplified reset - in production you'd want more sophisticated cleanup
    end

    private def self.increment_metric(metric_name : String) : Nil
      key = build_metrics_key(metric_name)
      Mosquito.backend.increment(key, "value")
    end

    private def self.get_metric(metric_name : String) : Int64
      key = build_metrics_key(metric_name)
      Mosquito.backend.get(key, "value").try(&.to_i64) || 0_i64
    end

    private def self.record_duration(duration_key : String, duration_ms : Int64) : Nil
      avg_key = build_metrics_key("#{duration_key}:avg")
      count_key = build_metrics_key("#{duration_key}:count")

      # Get current average and count
      current_avg = Mosquito.backend.get(avg_key, "value").try(&.to_f) || 0.0
      current_count = Mosquito.backend.get(count_key, "value").try(&.to_i64) || 0_i64

      # Calculate new average
      new_count = current_count + 1
      new_avg = ((current_avg * current_count) + duration_ms) / new_count

      # Update values
      Mosquito.backend.set(avg_key, "value", new_avg.to_s)
      Mosquito.backend.set(count_key, "value", new_count.to_s)
    end

    private def self.build_metrics_key(*parts) : String
      Mosquito::Backend.build_key(METRICS_KEY_PREFIX, *parts)
    end
  end
end
