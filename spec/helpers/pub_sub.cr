class PubSub
  def self.instance
    @@instance ||= new
  end

  def self.eavesdrop : Array(Mosquito::Backend::BroadcastMessage)
    instance.receive_messages
    yield
    instance.stop_listening
    instance.messages
  end

  getter messages = [] of Mosquito::Backend::BroadcastMessage
  @channel = Channel(Mosquito::Backend::BroadcastMessage).new
  @stopping_channel = Channel(Bool).new

  def initialize
  end

  def receive_messages
    @continue_receiving = true
    spawn receive_loop
    @channel = Mosquito.backend.subscribe "mosquito:*"
  end

  def stop_listening
    @continue_receiving = false
  end

  def receive_loop
    loop do
      break unless @continue_receiving
      select
      when message = @channel.receive
        @messages << message
      when timeout(500.milliseconds)
      end
    end
    @channel.close
  end

  delegate clear, to: @messages

  module Helpers
    delegate eavesdrop, to: PubSub
    def assert_message_received(matcher : Regex) : Nil
      PubSub.instance.messages.find do |message|
        matcher === message.message
      end
    end
  end
end
