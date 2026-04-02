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

  # Returns a `ConcurrencyConfig` instance for reading and writing the
  # remotely stored concurrency limits used by
  # `RemoteConfigDequeueAdapter`.
  def self.concurrency_config : ConcurrencyConfig
    ConcurrencyConfig.instance
  end

  # Convenience reader for the current global remote concurrency limits.
  def self.concurrency_limits : Hash(String, Int32)
    concurrency_config.limits
  end

  # Convenience reader for a specific overseer's concurrency limits.
  def self.concurrency_limits(overseer_id : String) : Hash(String, Int32)
    concurrency_config.limits(overseer_id)
  end

  # Convenience writer — replaces the global stored concurrency limits so
  # that all `RemoteConfigDequeueAdapter` instances pick them up on their
  # next refresh cycle.
  def self.set_concurrency_limits(limits : Hash(String, Int32)) : Nil
    concurrency_config.update(limits)
  end

  # Convenience writer — replaces stored concurrency limits for a specific
  # overseer.
  def self.set_concurrency_limits(limits : Hash(String, Int32), overseer_id : String) : Nil
    concurrency_config.update(limits, overseer_id)
  end

  # Returns an `ExecutorConfig` instance for reading and writing the
  # remotely stored executor count.
  def self.executor_config : ExecutorConfig
    ExecutorConfig.instance
  end

  # Convenience reader for the global remote executor count.
  def self.executor_count : Int32?
    executor_config.executor_count
  end

  # Convenience reader for a specific overseer's executor count.
  def self.executor_count(overseer_id : String) : Int32?
    executor_config.executor_count(overseer_id)
  end

  # Convenience writer — sets the global executor count override.
  def self.set_executor_count(count : Int32) : Nil
    executor_config.update(count)
  end

  # Convenience writer — sets the executor count for a specific overseer.
  def self.set_executor_count(count : Int32, overseer_id : String) : Nil
    executor_config.update(count, overseer_id)
  end
end
