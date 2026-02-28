require "../src/mosquito"

Mosquito.configure do |settings|
  settings.connection_string = ENV["REDIS_URL"]? || "redis://localhost:6379/3"
  settings.idle_wait = 1.second
end

Mosquito.configuration.backend.flush

Log.setup do |c|
  backend = Log::IOBackend.new

  c.bind "redis.*", :warn, backend
  c.bind "mosquito.*", :debug, backend
end

require "./jobs/*"

def expect_run_count(klass, expected)
  metadata = klass.metadata.to_h
  if (run_count = metadata["run_count"].to_i) != expected
    raise "Expected #{klass.name} to have run_count == #{expected}.  But got #{run_count}"
  else
    puts "#{klass.name} was executed correctly."
  end
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

Mosquito::Runner.start(spin: false)

count = 0
while count <= 19 && Mosquito::Runner.keep_running
  sleep 1.second
  count += 1
end

Mosquito::Runner.stop(wait: true)

puts "End of demo."
puts "----------------------------------"
puts "Checking integration test flags..."

expect_run_count(PeriodicallyPuts, 7)
expect_run_count(QueuedJob, 1)
expect_run_count(CustomSerializersJob, 3)
expect_run_count(RateLimitedJob, 3)
