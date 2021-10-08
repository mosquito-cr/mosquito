require "../src/mosquito"

Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/3"
end

Mosquito::Redis.instance.flushall

require "./jobs/*"

def expect_run_count(klass, expected)
  actual = Mosquito::Redis.instance.get klass.name.underscore
  if expected.to_s != actual
    raise "Expected #{klass.name} to have performed #{expected} times but instead it was performed #{actual} times."
  else
    puts "#{klass.name} executed correctly."
  end
end

def expect_executed_count(klass, expected)
  config = Mosquito::Redis.instance.retrieve_hash(klass.queue.config_key)
  if config["executed"] != expected
    raise "Expected #{klass.name} to have config.executed == #{expected}.  But got #{config["executed"]}"
  else
    puts "#{klass.name} was throttled correctly."
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

expect_run_count(ThrottledJob, 9)
expect_executed_count(ThrottledJob, "0")
