require "../src/mosquito"
require "./jobs/*"

Mosquito.configure do |settings|
  settings.backend_connection_string = ENV["REDIS_URL"]? || "redis://localhost:6379/4"
  settings.publish_metrics = true
end

Mosquito.configuration.backend.flush

Log.setup do |c|
  backend = Log::IOBackend.new

  c.bind "redis.*", :error, backend
  c.bind "mosquito.*", :error, backend
end

stopping = false
Signal::INT.trap do
  if stopping
    puts "SIGINT received again, crash-exiting."
    exit 1
  end

  Mosquito::Runner.stop
  stopping = true
end

Mosquito::Runner.start spin: false

EventCount = 500
events = Deque(Time).new(EventCount)
event_count = 0
missed_messages = 0

channel = Mosquito.backend.subscribe(EmitMessageJob::PUBSUB_CHANNEL)

print "enqueuing benchmark jobs..."
10000.times {
  EmitMessageJob.new.enqueue
}
puts "done"

spawn do
  loop do
    break unless Mosquito::Runner.keep_running
    if missed_messages >= 100
      Mosquito::Runner.stop
      break
    end

    select
    when channel.receive
      events << Time.utc
      event_count += 1
    when timeout(100.milliseconds)
      missed_messages += 1
    end
  end
end

message = ->(span : Time::Span) do
  print "\r"
  print "Events: #{event_count} | "
  print "Span: #{span.total_seconds.round(2)} | "
  print "Rate: #{events.size.to_f./(span.to_f).round(2)} events/sec"
  print "    "
end

loop do
  break unless Mosquito::Runner.keep_running

  # if events.size >= EventCount
  #   (events.size - EventCount).times { events.shift }
  # end

  unless events.size >= 10
    print "\r"
    print "Waiting for events..."
    sleep 0.1.seconds
    next
  end

  message.call events.last - events.first
end

Mosquito::Runner.stop wait: true



puts
print "Total events: #{event_count} | "
print "Rate: #{events.size.to_f./(events.last.-(events.first).to_f).round(2)} events/sec"
puts
