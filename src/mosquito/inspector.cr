require "./inspector/*"

module Mosquito::Inspector
  def self.list_queues : Array(Inspector::Queue)
    Mosquito.backend.list_queues
      .map { |name| Inspector::Queue.new name }
  end

  def self.list_runners : Array(Runner)
    Mosquito.backend.list_runners
      .map { |name| Runner.new name }
  end

  def self.event_receiver : Channel(Backend::BroadcastMessage)
    Mosquito.backend.subscribe "mosquito:*"
  end

  def self.queue(name : String) : Inspector::Queue
    Inspector::Queue.new name
  end
end
