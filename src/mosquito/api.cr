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

  def self.list_periodic_jobs : Array(PeriodicJob)
    PeriodicJob.all
  end

  def self.list_queues : Array(Observability::Queue)
    Mosquito.backend.list_queues
      .map { |name| Observability::Queue.new name }
  end

  def self.list_overseers : Array(Overseer)
    Mosquito.backend.list_overseers
      .map { |name| Overseer.new name }
  end

  def self.event_receiver : Channel(Backend::BroadcastMessage)
    Mosquito.backend.subscribe "mosquito:*"
  end
end
