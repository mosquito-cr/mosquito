module Mosquito::Observability::Publisher
  @[AlwaysInline]
  def publish(data : NamedTuple)
    metrics do
      Log.debug { "Publishing #{data} to #{@publish_context.originator}" }
      PubSub.instance.capture_message(@publish_context.originator, data.to_json)
    end
  end
end

class PubSub
  def self.instance
    @@instance ||= new
  end

  def self.eavesdrop : Array(Mosquito::Backend::BroadcastMessage)
    instance.listen
    yield
    instance.messages
  ensure
    instance.stop_listening
  end

  getter messages = [] of Mosquito::Backend::BroadcastMessage

  def initialize
    @listening = false
  end

  def listen
    @listening = true
  end

  def stop_listening
    @listening = false
  end

  def capture_message(originator : String, message : String)
    if @listening
      @messages << Mosquito::Backend::BroadcastMessage.new(originator, message)
    end
  end

  delegate clear, to: @messages

  module Helpers
    delegate eavesdrop, to: PubSub

    def assert_message_received(matcher : Regex) : Nil
      found = PubSub.instance.messages.find do |message|
        matcher === message.message
      end

      assert found, "Expected to find a message matching #{matcher.inspect}, but only found: #{PubSub.instance.messages.map(&.message).inspect}"
    end
  end
end
