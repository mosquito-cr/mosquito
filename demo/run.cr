require "../src/mosquito"

Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/3"
end

Mosquito::Redis.instance.flushall

require "./jobs/*"

def expect_run_count(klass, expected)
  metadata = klass.metadata.to_h
  if (run_count = metadata["run_count"].to_i) != expected
    raise "Expected #{klass.name} to have run_count == #{expected}.  But got #{run_count}"
  else
    puts "#{klass.name} was executed correctly."
  end
end

spawn do
  Mosquito::Runner.start
end

sleep 21

puts "End of demo."
puts "----------------------------------"
puts "Checking integration test flags..."

expect_run_count(PeriodicallyPuts, 7)
expect_run_count(QueuedJob, 1)
expect_run_count(CustomSerializersJob, 3)
