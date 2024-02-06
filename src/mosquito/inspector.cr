require "./inspector/*"

module Mosquito::Inspector
  def self.overseer(id : String) : Overseer
    Overseer.new id
  end

  def self.executor(id : String) : Executor
    Executor.new id
  end

  def self.list_queues : Array(Inspector::Queue)
    Mosquito.backend.list_queues
      .map { |name| Inspector::Queue.new name }
  end

  def self.list_overseers : Array(Overseer)
    Mosquito.backend.list_overseers
      .map { |name| Overseer.new name }
  end

  def self.event_receiver : Channel(Backend::BroadcastMessage)
    Mosquito.backend.subscribe "mosquito:*"
  end

  def self.queue(name : String) : Inspector::Queue
    Inspector::Queue.new name
  end
end
