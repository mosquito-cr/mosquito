#!/usr/bin/env crystal

# Dashboard API Example
# This example demonstrates how to use the new Mosquito API
# for building web dashboards similar to Sidekiq's web interface.

require "../src/mosquito"

# Configure Mosquito
Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/0"
  settings.publish_metrics = true # Enable metrics tracking
end

# Example job classes for demonstration
class DemoEmailJob < Mosquito::QueuedJob
  param email : String
  param subject : String

  def perform
    puts "Sending email to #{email} with subject: #{subject}"
    # Simulate some work
    sleep rand(0.1..0.5)

    # Randomly fail sometimes for demo purposes
    if rand(10) == 0
      fail "Failed to send email"
    end
  end
end

class DemoReportJob < Mosquito::QueuedJob
  queue_name "reports"

  param report_type : String
  param user_id : Int32

  def perform
    puts "Generating #{report_type} report for user #{user_id}"
    sleep rand(1.0..3.0) # Simulate longer work
  end
end

# Register the jobs
Mosquito::Base.register_job_mapping "demo_email_job", DemoEmailJob
Mosquito::Base.register_job_mapping "demo_report_job", DemoReportJob

puts "Mosquito Dashboard API Demo"
puts "==========================="

# Create some demo jobs
puts "\n1. Enqueuing some demo jobs..."
5.times do |i|
  DemoEmailJob.new(
    email: "user#{i}@example.com",
    subject: "Welcome to Mosquito!"
  ).enqueue
end

3.times do |i|
  DemoReportJob.new(
    report_type: "monthly",
    user_id: i + 1
  ).enqueue
end

# Schedule some jobs for the future
2.times do |i|
  DemoEmailJob.new(
    email: "future#{i}@example.com",
    subject: "Scheduled email"
  ).enqueue(in: 10.minutes)
end

puts "Jobs enqueued successfully!"

# Demonstrate the API capabilities
puts "\n2. Dashboard Overview Data:"
puts "-" * 40

overview = Mosquito::Api::WebInterface.dashboard_overview
puts "Cluster Health: #{overview["cluster_health"]}"
puts "Total Jobs: #{overview["global_stats"].as(Hash)["total_jobs"]}"

puts "\n3. Queue Information:"
puts "-" * 40

queues_data = Mosquito::Api::WebInterface.queues_index
queues = queues_data["queues"].as(Array)

queues.each do |queue_data|
  queue_info = queue_data.as(Hash)
  name = queue_info["name"]
  total = queue_info["total_size"]
  details = queue_info["size_details"].as(Hash)

  puts "Queue: #{name}"
  puts "  Total jobs: #{total}"
  puts "  Waiting: #{details["waiting"]}, Scheduled: #{details["scheduled"]}"
  puts "  Pending: #{details["pending"]}, Dead: #{details["dead"]}"
  puts
end

puts "\n4. Worker Status:"
puts "-" * 40

workers_data = Mosquito::Api::WebInterface.workers_index
overseers = workers_data["overseers"].as(Array)

if overseers.empty?
  puts "No active workers (start some Mosquito workers to see them here)"
else
  overseers.each do |overseer_data|
    overseer_info = overseer_data.as(Hash)
    puts "Overseer: #{overseer_info["instance_id"]}"

    executors = overseer_info["executors"].as(Array)
    puts "  Executors: #{executors.size}"

    executors.each do |executor_data|
      executor_info = executor_data.as(Hash)
      current_job = executor_info["current_job"]
      if current_job
        puts "    Executor #{executor_info["instance_id"]}: Working on #{current_job}"
      else
        puts "    Executor #{executor_info["instance_id"]}: Idle"
      end
    end
    puts
  end
end

puts "\n5. System Health Check:"
puts "-" * 40

health_data = Mosquito::Api::WebInterface.health_check
status = health_data["status"].as(String)
details = health_data["details"].as(Hash)

puts "Status: #{status.upcase}"
puts "Total Jobs: #{details["total_jobs"]}"
puts "Dead Jobs Ratio: #{(details["dead_jobs_ratio"].as(Float64) * 100).round(2)}%"
puts "Executor Utilization: #{details["executor_utilization"].as(Float64).round(2)}%"
puts "Active Executors: #{details["active_executors"]}"

puts "\n6. Metrics Example:"
puts "-" * 40

# Show global metrics
global_metrics = Mosquito::Api::WebInterface.metrics
metrics = global_metrics["metrics"].as(Hash)

puts "Global Metrics:"
puts "  Total Enqueued: #{metrics["total_enqueued"]}"
puts "  Total Finished: #{metrics["total_finished"]}"
puts "  Total Failed: #{metrics["total_failed"]}"
puts "  Success Rate: #{metrics["global_success_rate"].as(Float64).round(2)}%"

puts "\n7. Recent Jobs by State:"
puts "-" * 40

# Show waiting jobs
waiting_jobs_data = Mosquito::Api::WebInterface.jobs_by_state("waiting", per_page: 3)
waiting_jobs = waiting_jobs_data["jobs"].as(Array)

puts "Recent Waiting Jobs:"
if waiting_jobs.empty?
  puts "  No waiting jobs"
else
  waiting_jobs.each do |job_data|
    job_info = job_data.as(Hash)
    puts "  #{job_info["type"]} (#{job_info["id"]}) - Enqueued: #{job_info["enqueue_time"]}"
  end
end

puts "\n8. Real-time Events Setup:"
puts "-" * 40

events_info = Mosquito::Api::WebInterface.events_stream
puts "WebSocket URL: #{events_info["websocket_url"]}"
puts "SSE URL: #{events_info["sse_url"]}"
puts "Available Event Types:"
event_types = events_info["event_types"].as(Array)
event_types.each do |event_type|
  puts "  - #{event_type}"
end

puts "\n" + "=" * 50
puts "API Demo Complete!"
puts "\nTo build a web dashboard:"
puts "1. Use the WebInterface module methods as JSON API endpoints"
puts "2. Connect to real-time events via WebSocket or SSE"
puts "3. Use the provided data structures to build your UI"
puts "\nExample HTTP API endpoints you could create:"
puts "  GET /api/dashboard          -> WebInterface.dashboard_overview"
puts "  GET /api/queues             -> WebInterface.queues_index"
puts "  GET /api/queues/:name       -> WebInterface.queue_details(name)"
puts "  GET /api/workers            -> WebInterface.workers_index"
puts "  GET /api/jobs/:id           -> WebInterface.job_details(id)"
puts "  GET /api/jobs?state=waiting -> WebInterface.jobs_by_state('waiting')"
puts "  GET /api/metrics            -> WebInterface.metrics"
puts "  GET /api/health             -> WebInterface.health_check"
puts "  GET /api/stats              -> WebInterface.stats_summary"
puts "  GET /api/events/stream      -> SSE stream"
puts "  GET /api/events/ws          -> WebSocket connection"
puts "\nSee demo/web_server_example.cr for a complete HTTP server implementation."
