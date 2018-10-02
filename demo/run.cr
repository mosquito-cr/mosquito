Mosquito::Redis.instance.flushall

require "../src/mosquito"
require "./jobs/*"

def expect_run_count(klass, expected)
  actual = Mosquito::Redis.instance.get klass.name.underscore
  if expected.to_s != actual
    raise "Expected #{klass.name} to have performed #{expected} times but instead it was performed #{actual} times."
  else
    puts "#{klass.name} executed correctly."
  end
end

spawn do
  Mosquito::Runner.start
end

sleep 10

puts "End of demo."
puts "----------------------------------"
puts "Checking integration test flags..."

expect_run_count(PeriodicallyPuts, 4)
expect_run_count(QueuedJob, 1)
expect_run_count(CustomSerializersJob, 3)
