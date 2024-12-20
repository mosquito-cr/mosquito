event_stream = Mosquito::Api.event_receiver
event_stream_clients = EventStream.new

def message_formatter(broadcast : Mosquito::Backend::BroadcastMessage) : String
  {
    type: "broadcast",
    channel: broadcast.channel,
    message: JSON.parse(broadcast.message)
  }.to_json
end

spawn do
  loop do
    message = event_stream.receive
    event_stream_clients.broadcast message_formatter(message)
  end
end

ws "/events" do |socket|
  event_stream_clients.register socket
end

