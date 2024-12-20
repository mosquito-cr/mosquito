class SocketBroadcaster
  @outputs = [] of HTTP::WebSocket

  delegate size, to: @outputs

  def initialize
  end

  def broadcast(message)
    @outputs.each do |output|
      output.send message
    end
  end

  def register(output : HTTP::WebSocket)
    @outputs << output
    output.on_close { @outputs.delete output }
  end
end
