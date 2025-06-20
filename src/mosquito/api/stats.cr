module Mosquito::Api
  # Represents global statistics for the entire Mosquito cluster
  class GlobalStats
    def initialize
    end

    # Total number of jobs across all queues and states
    def total_jobs : Int64
      Mosquito::Api.list_queues.sum(&.total_size)
    end

    # Total number of waiting jobs across all queues
    def waiting_jobs : Int64
      Mosquito::Api.list_queues.sum(&.waiting_size)
    end

    # Total number of scheduled jobs across all queues
    def scheduled_jobs : Int64
      Mosquito::Api.list_queues.sum(&.scheduled_size)
    end

    # Total number of pending jobs across all queues
    def pending_jobs : Int64
      Mosquito::Api.list_queues.sum(&.pending_size)
    end

    # Total number of dead jobs across all queues
    def dead_jobs : Int64
      Mosquito::Api.list_queues.sum(&.dead_size)
    end

    # Number of active overseers
    def active_overseers : Int32
      Mosquito::Api.list_overseers.size
    end

    # Number of active executors
    def active_executors : Int32
      Mosquito::Api.list_executors.size
    end

    # Number of busy executors (currently executing jobs)
    def busy_executors : Int32
      Mosquito::Api.list_executors.count { |executor| !executor.current_job.nil? }
    end

    # Number of idle executors
    def idle_executors : Int32
      active_executors - busy_executors
    end

    # Number of queues
    def queue_count : Int32
      Mosquito::Api.list_queues.size
    end

    # Jobs processed rate (estimated from pending queue movement)
    def processing_rate : Float64
      # This is a simple estimation - in a real implementation you'd track this over time
      busy_executors.to_f
    end

    def to_h : Hash(String, Int64 | Int32 | Float64)
      {
        "total_jobs"       => total_jobs,
        "waiting_jobs"     => waiting_jobs,
        "scheduled_jobs"   => scheduled_jobs,
        "pending_jobs"     => pending_jobs,
        "dead_jobs"        => dead_jobs,
        "active_overseers" => active_overseers,
        "active_executors" => active_executors,
        "busy_executors"   => busy_executors,
        "idle_executors"   => idle_executors,
        "queue_count"      => queue_count,
        "processing_rate"  => processing_rate,
      }
    end
  end

  # Represents statistics for a specific queue
  class QueueStats
    getter queue : Queue

    def initialize(@queue : Queue)
    end

    delegate name, to: queue

    def waiting_count : Int64
      queue.waiting_size
    end

    def scheduled_count : Int64
      queue.scheduled_size
    end

    def pending_count : Int64
      queue.pending_size
    end

    def dead_count : Int64
      queue.dead_size
    end

    def total_count : Int64
      queue.total_size
    end

    def processing_rate : Float64
      # Simple estimation - could be enhanced with historical data
      pending_count.to_f
    end

    def to_h : Hash(String, String | Int64 | Float64)
      {
        "name"            => name,
        "waiting_count"   => waiting_count,
        "scheduled_count" => scheduled_count,
        "pending_count"   => pending_count,
        "dead_count"      => dead_count,
        "total_count"     => total_count,
        "processing_rate" => processing_rate,
      }
    end
  end

  # Represents cluster-wide statistics and health information
  class ClusterStats
    def initialize
    end

    # Overall cluster health status
    def health_status : String
      if dead_jobs_ratio > 0.1
        "unhealthy"
      elsif dead_jobs_ratio > 0.05
        "warning"
      else
        "healthy"
      end
    end

    # Ratio of dead jobs to total jobs
    def dead_jobs_ratio : Float64
      total = total_jobs
      return 0.0 if total == 0
      dead_jobs.to_f / total.to_f
    end

    # Average jobs per queue
    def avg_jobs_per_queue : Float64
      queues = queue_count
      return 0.0 if queues == 0
      total_jobs.to_f / queues.to_f
    end

    # Executor utilization percentage
    def executor_utilization : Float64
      total = active_executors
      return 0.0 if total == 0
      (busy_executors.to_f / total.to_f) * 100.0
    end

    private def global_stats
      @global_stats ||= GlobalStats.new
    end

    delegate total_jobs, waiting_jobs, scheduled_jobs, pending_jobs, dead_jobs,
      active_overseers, active_executors, busy_executors, idle_executors,
      queue_count, processing_rate, to: global_stats

    def to_h : Hash(String, String | Int64 | Int32 | Float64)
      global_stats.to_h.merge({
        "health_status"        => health_status,
        "dead_jobs_ratio"      => dead_jobs_ratio,
        "avg_jobs_per_queue"   => avg_jobs_per_queue,
        "executor_utilization" => executor_utilization,
      })
    end
  end
end
