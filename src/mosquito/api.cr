require "./backend"
require "./api/observability/*"
require "./api/*"

module Mosquito::Api
  def self.overseer(id : String) : Overseer
    Overseer.new id
  end

  def self.executor(id : String) : Executor
    Executor.new id
  end

  def self.job_run(id : String) : JobRun
    JobRun.new id
  end

  def self.queue(name : String) : Queue
    Queue.new name
  end

  def self.list_queues : Array(Queue)
    Mosquito.backend.list_queues
      .map { |name| Queue.new name }
  end

  def self.list_overseers : Array(Overseer)
    Mosquito.backend.list_overseers
      .map { |name| Overseer.new name }
  end

  def self.list_executors : Array(Executor)
    list_overseers.flat_map(&.executors)
  end

  def self.cluster_stats : ClusterStats
    ClusterStats.new
  end

  def self.queue_stats : Hash(String, QueueStats)
    result = {} of String => QueueStats
    list_queues.each do |queue|
      result[queue.name] = QueueStats.new(queue)
    end
    result
  end

  def self.global_stats : GlobalStats
    GlobalStats.new
  end

  def self.event_receiver : Channel(Backend::BroadcastMessage)
    Mosquito.backend.subscribe "mosquito:*"
  end

  def self.job_runs_by_state(state : String, queue_name : String? = nil, limit : Int32 = 100) : Array(JobRun)
    case state
    when "waiting"
      if queue_name
        Queue.new(queue_name).waiting_job_runs.first(limit)
      else
        list_queues.flat_map(&.waiting_job_runs).first(limit)
      end
    when "pending"
      if queue_name
        Queue.new(queue_name).pending_job_runs.first(limit)
      else
        list_queues.flat_map(&.pending_job_runs).first(limit)
      end
    when "scheduled"
      if queue_name
        Queue.new(queue_name).scheduled_job_runs.first(limit)
      else
        list_queues.flat_map(&.scheduled_job_runs).first(limit)
      end
    when "dead"
      if queue_name
        Queue.new(queue_name).dead_job_runs.first(limit)
      else
        list_queues.flat_map(&.dead_job_runs).first(limit)
      end
    else
      [] of JobRun
    end
  end
end
