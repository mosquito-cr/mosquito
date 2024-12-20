require "./socket_broadcaster"

class EventStream < SocketBroadcaster
  def register(output : HTTP::WebSocket)
    super
    output.on_message do |message|
      message_received(output, message)
    end
  end

  def message_received(socket : HTTP::WebSocket, message : String)
    case message
    when "ping"
      socket.send({ type: "pong" }.to_json)
    else
      Log.error { "Unknown message received: #{message}" }
    end
  end
end

