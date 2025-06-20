require "../src/mosquito"

# Example demonstrating new backend monitoring features

# Configure backend (using Redis for this example)
Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/0"
end

# Create some test jobs
class MonitoringTestJob < Mosquito::QueuedJob
  param message : String

  def perform
    log "Processing: #{message}"
  end
end

puts "=== Mosquito Backend Monitoring Example ==="
puts

# 1. Check backend health
puts "1. Backend Health Check"
if Mosquito.backend.healthy?
  puts "   ✓ Backend is healthy"
else
  puts "   ✗ Backend has issues"
end

# Get connection info
info = Mosquito.backend.connection_info
puts "   Connection info: #{info}" unless info.empty?
puts

# 2. Enqueue some test jobs
puts "2. Enqueueing Test Jobs"
backend = Mosquito.backend.named("monitoring_test")

# Single enqueue
job1 = MonitoringTestJob.new(message: "Single job").enqueue
puts "   Enqueued single job: #{job1.id}"

# Batch enqueue (using default implementation)
jobs = (1..5).map do |i|
  job_run = MonitoringTestJob.new(message: "Batch job #{i}").build_job_run
  job_run.store
  job_run
end
backend.enqueue_batch(jobs)
puts "   Enqueued batch of #{jobs.size} jobs"
puts

# 3. Check queue sizes
puts "3. Queue Sizes"
puts "   Waiting: #{backend.waiting_size}"
puts "   Scheduled: #{backend.scheduled_size}"
puts "   Pending: #{backend.pending_size}"
puts "   Dead: #{backend.dead_size}"
puts "   Total: #{backend.size(include_dead: true)}"
puts

# 4. Get global queue statistics
puts "4. Global Queue Statistics"
stats = Mosquito.backend.queue_stats
stats.each do |queue_name, counts|
  total = counts["total"]? || 0
  if total > 0
    puts "   #{queue_name}:"
    counts.each do |state, count|
      puts "     #{state}: #{count}"
    end
  end
end
puts

# 5. Dequeue batch
puts "5. Batch Dequeue"
dequeued = backend.dequeue_batch(limit: 3)
puts "   Dequeued #{dequeued.size} jobs in batch"
dequeued.each do |job|
  puts "   - #{job.id}: #{job.config["message"]?}"
  backend.finish(job) # Mark as complete
end
puts

# 6. Find a specific job
puts "6. Job Search"
if remaining_job = backend.dequeue
  job_id = remaining_job.id
  backend.finish(remaining_job) # Put it back

  if found = backend.find_job(job_id)
    puts "   ✓ Found job #{job_id}"
  else
    puts "   ✗ Could not find job #{job_id}"
  end
end
puts

# 7. Transaction example (works with any backend, but only atomic with PostgreSQL)
puts "7. Transaction Support"
backend.transaction do
  puts "   Creating related jobs in transaction..."
  parent = MonitoringTestJob.new(message: "Parent job").build_job_run
  parent.store
  backend.enqueue(parent)

  child = MonitoringTestJob.new(message: "Child job").build_job_run
  child.store
  backend.enqueue(child)

  puts "   ✓ Transaction complete"
end
puts

# 8. Cleanup
puts "8. Maintenance"
expired_count = Mosquito.backend.cleanup_expired
puts "   Cleaned up #{expired_count} expired entries"

# Clean up our test queue
backend.flush
puts "   Flushed test queue"
puts

puts "=== Example Complete ==="
