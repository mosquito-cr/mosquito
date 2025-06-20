require "json"

module Mosquito::Api
  # Provides a web-friendly JSON interface for dashboard applications
  # This module contains methods that return JSON-serializable data structures
  # suitable for HTTP API endpoints
  module WebInterface
    # Dashboard overview data
    def self.dashboard_overview
      global_stats = Api.global_stats
      queue_stats = Api.queue_stats

      {
        "timestamp"      => Time.utc.to_unix,
        "global_stats"   => global_stats.to_h,
        "queue_summary"  => queue_stats.transform_values(&.to_h),
        "cluster_health" => Api.cluster_stats.health_status,
      }
    end

    # Queue listing with basic stats
    def self.queues_index
      {
        "timestamp" => Time.utc.to_unix,
        "queues"    => Api.list_queues.map do |queue|
          {
            "name"         => queue.name,
            "size_details" => queue.size_details,
            "total_size"   => queue.total_size,
          }
        end,
      }
    end

    # Detailed queue information
    def self.queue_details(queue_name : String)
      queue = Api.queue(queue_name)
      metrics = Api::Metrics.queue_metrics(queue_name)

      {
        "timestamp" => Time.utc.to_unix,
        "queue"     => {
          "name"         => queue.name,
          "size_details" => queue.size_details,
          "total_size"   => queue.total_size,
        },
        "metrics"     => metrics,
        "recent_jobs" => {
          "waiting" => serialize_job_runs(queue.waiting_job_runs.first(10)),
          "pending" => serialize_job_runs(queue.pending_job_runs.first(10)),
          "dead"    => serialize_job_runs(queue.dead_job_runs.first(10)),
        },
      }
    end

    # Workers and their current status
    def self.workers_index
      overseers = Api.list_overseers

      {
        "timestamp" => Time.utc.to_unix,
        "overseers" => overseers.map do |overseer|
          {
            "instance_id"    => overseer.instance_id,
            "last_heartbeat" => overseer.last_heartbeat.try(&.to_unix),
            "executors"      => overseer.executors.map do |executor|
              {
                "instance_id"       => executor.instance_id,
                "current_job"       => executor.current_job,
                "current_job_queue" => executor.current_job_queue,
                "last_heartbeat"    => executor.heartbeat.try(&.to_unix),
              }
            end,
          }
        end,
      }
    end

    # Job details
    def self.job_details(job_id : String)
      job_run = Api.job_run(job_id)

      unless job_run.found?
        return {
          "error"  => "Job not found",
          "job_id" => job_id,
        }
      end

      {
        "timestamp" => Time.utc.to_unix,
        "job"       => job_run.to_h,
      }
    end

    # Jobs by state with pagination
    def self.jobs_by_state(state : String, queue_name : String? = nil, page : Int32 = 1, per_page : Int32 = 50)
      offset = (page - 1) * per_page
      job_runs = Api.job_runs_by_state(state, queue_name, per_page + offset)

      # Simple pagination
      paginated_jobs = job_runs.skip(offset).first(per_page)

      {
        "timestamp"  => Time.utc.to_unix,
        "jobs"       => serialize_job_runs(paginated_jobs),
        "pagination" => {
          "page"          => page,
          "per_page"      => per_page,
          "total_fetched" => job_runs.size,
          "has_more"      => job_runs.size > offset + per_page,
        },
        "filters" => {
          "state"      => state,
          "queue_name" => queue_name,
        },
      }
    end

    # Metrics endpoint
    def self.metrics(queue_name : String? = nil, job_type : String? = nil)
      metrics = if queue_name && job_type
                  Api::Metrics.job_type_metrics(queue_name, job_type)
                elsif queue_name
                  Api::Metrics.queue_metrics(queue_name)
                else
                  Api::Metrics.global_metrics
                end

      {
        "timestamp" => Time.utc.to_unix,
        "metrics"   => metrics,
        "filters"   => {
          "queue_name" => queue_name,
          "job_type"   => job_type,
        },
      }
    end

    # Real-time events stream setup
    def self.events_stream
      {
        "message"       => "Connect to WebSocket or Server-Sent Events endpoint for real-time updates",
        "websocket_url" => "/api/events/ws",
        "sse_url"       => "/api/events/stream",
        "event_types"   => [
          "job-started",
          "job-finished",
          "enqueued",
          "dequeued",
          "executor-created",
          "executor-died",
          "overseer-starting",
          "overseer-stopping",
          "overseer-stopped",
        ],
      }
    end

    # System health check
    def self.health_check
      cluster_stats = Api.cluster_stats

      {
        "timestamp" => Time.utc.to_unix,
        "status"    => cluster_stats.health_status,
        "details"   => {
          "total_jobs"           => cluster_stats.total_jobs,
          "dead_jobs_ratio"      => cluster_stats.dead_jobs_ratio,
          "executor_utilization" => cluster_stats.executor_utilization,
          "active_executors"     => cluster_stats.active_executors,
          "active_overseers"     => cluster_stats.active_overseers,
        },
      }
    end

    # Statistics summary
    def self.stats_summary
      global_stats = Api.global_stats
      cluster_stats = Api.cluster_stats

      {
        "timestamp" => Time.utc.to_unix,
        "summary"   => {
          "jobs" => {
            "total"     => global_stats.total_jobs,
            "waiting"   => global_stats.waiting_jobs,
            "scheduled" => global_stats.scheduled_jobs,
            "pending"   => global_stats.pending_jobs,
            "dead"      => global_stats.dead_jobs,
          },
          "workers" => {
            "overseers" => global_stats.active_overseers,
            "executors" => {
              "total" => global_stats.active_executors,
              "busy"  => global_stats.busy_executors,
              "idle"  => global_stats.idle_executors,
            },
          },
          "performance" => {
            "processing_rate"      => global_stats.processing_rate,
            "executor_utilization" => cluster_stats.executor_utilization,
            "health_status"        => cluster_stats.health_status,
          },
        },
      }
    end

    # Helper method to serialize job runs for JSON responses
    private def self.serialize_job_runs(job_runs : Array(JobRun))
      job_runs.map(&.to_h)
    end

    # JSON response wrapper with proper headers
    def self.json_response(data)
      {
        "data"         => data,
        "api_version"  => "1.0",
        "generated_at" => Time.utc.to_rfc3339,
      }.to_json
    end

    # Error response wrapper
    def self.error_response(message : String, code : String = "error", status : Int32 = 500)
      {
        "error" => {
          "message" => message,
          "code"    => code,
          "status"  => status,
        },
        "api_version"  => "1.0",
        "generated_at" => Time.utc.to_rfc3339,
      }.to_json
    end
  end
end
