require "../socket_broadcaster"

hot_reload = SocketBroadcaster.new

# '.' is relative to app root
FSWatch.watch "." do |event|
  next if /\.git/ =~ event.path
  hot_reload.broadcast("hot reload")
end

ws "/hot-reload" do |socket|
  hot_reload.register socket
end

