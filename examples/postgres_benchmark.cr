require "../src/mosquito"
require "../src/mosquito/postgres_backend"
require "benchmark"

# Configure PostgreSQL backend
Mosquito::PostgresBackend.connection_url = ENV["DATABASE_URL"]? || "postgres://mosquito:mosquito@localhost:5433/mosquito_test"

# Ensure clean state
Mosquito::PostgresBackend.flush

backend = Mosquito::PostgresBackend.new("benchmark_queue")

puts "PostgreSQL Backend Performance Benchmark"
puts "=" * 40

# Benchmark individual enqueues vs batch enqueue
job_count = 1000

puts "\nEnqueuing #{job_count} jobs..."

# Individual enqueues
individual_time = Benchmark.measure do
  job_count.times do |i|
    job_run = Mosquito::JobRun.new("individual_job_#{i}")
    job_run.store
    backend.enqueue(job_run)
  end
end

puts "Individual enqueues: #{individual_time.real.round(3)}s (#{(job_count / individual_time.real).round(2)} jobs/sec)"

# Clean up
backend.flush

# Batch enqueue
batch_time = Benchmark.measure do
  job_runs = (1..job_count).map do |i|
    Mosquito::JobRun.new("batch_job_#{i}").tap(&.store)
  end
  backend.enqueue_batch(job_runs)
end

puts "Batch enqueue: #{batch_time.real.round(3)}s (#{(job_count / batch_time.real).round(2)} jobs/sec)"
puts "Speedup: #{(individual_time.real / batch_time.real).round(2)}x"

# Benchmark dequeue operations
puts "\n" + "=" * 40
puts "Dequeuing #{job_count} jobs..."

# Verify we have jobs to dequeue
actual_count = backend.size

dequeue_time = Benchmark.measure do
  actual_count.times do
    if job = backend.dequeue
      # Process the job (in real usage, this would be executed)
      backend.finish(job)
    end
  end
end

puts "Dequeue rate: #{(actual_count / dequeue_time.real).round(2)} jobs/sec"

# Test cleanup performance
puts "\n" + "=" * 40
puts "Testing cleanup performance..."

# Add expired entries
100.times do |i|
  Mosquito::PostgresBackend.store("expired_#{i}", {"data" => "test"})
  Mosquito::PostgresBackend.delete("expired_#{i}", in: -1.seconds)
end

# Add expired locks
Mosquito::PostgresBackend.with_connection do |db|
  100.times do |i|
    db.exec(<<-SQL, "expired_lock_#{i}", "test", Time.utc - 1.minute)
      INSERT INTO mosquito_locks (key, value, expires_at)
      VALUES ($1, $2, $3)
    SQL
  end
end

cleanup_time = Benchmark.measure do
  deleted = Mosquito::PostgresBackend.cleanup_expired
  puts "Cleaned up #{deleted} expired entries"
end

puts "Cleanup time: #{cleanup_time.real.round(3)}s"

# Connection pool test
puts "\n" + "=" * 40
puts "Testing connection pooling with concurrent operations..."

concurrent_time = Benchmark.measure do
  channel = Channel(Nil).new

  20.times do |i|
    spawn do
      job = Mosquito::JobRun.new("concurrent_#{i}").tap(&.store)
      backend.enqueue(job)
      channel.send(nil)
    end
  end

  20.times { channel.receive }
end

puts "Concurrent operations completed in: #{concurrent_time.real.round(3)}s"

# Clean up
Mosquito::PostgresBackend.flush
puts "\nBenchmark completed!"
