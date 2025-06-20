require "../src/mosquito"

# Configure Mosquito to use PostgreSQL backend
Mosquito.configure do |settings|
  settings.backend = Mosquito::PostgresBackend
end

# Set the database connection
# You can also use DATABASE_URL environment variable
Mosquito::PostgresBackend.connection_url = ENV["DATABASE_URL"]? || "postgres://localhost/mosquito_example"

# Define a simple job
class WelcomeEmailJob < Mosquito::QueuedJob
  params(
    user_id : Int32,
    email : String,
    name : String
  )

  def perform
    Log.info { "Sending welcome email to #{name} (#{email})" }
    # Simulate email sending
    sleep 0.5
    Log.info { "Welcome email sent to user #{user_id}" }
  end
end

# Define a scheduled job
class DailyReportJob < Mosquito::PeriodicJob
  run_every 1.day

  def perform
    Log.info { "Generating daily report..." }
    # Simulate report generation
    sleep 1
    Log.info { "Daily report completed" }
  end
end

# Example usage
if ARGV.includes?("--worker")
  # Run as a worker
  Log.info { "Starting Mosquito worker with PostgreSQL backend..." }
  Mosquito::Runner.start
else
  # Enqueue some jobs
  Log.info { "Enqueuing jobs to PostgreSQL backend..." }

  # Enqueue immediate job
  WelcomeEmailJob.new(
    user_id: 123,
    email: "user@example.com",
    name: "John Doe"
  ).enqueue

  # Schedule a job for later
  WelcomeEmailJob.new(
    user_id: 456,
    email: "another@example.com",
    name: "Jane Smith"
  ).enqueue(in: 30.seconds)

  Log.info { "Jobs enqueued! Run with --worker flag to process them." }

  # Show queue status
  backend = Mosquito.backend
  queues = backend.list_queues

  Log.info { "Active queues: #{queues.join(", ")}" }

  queues.each do |queue_name|
    queue = backend.named(queue_name)
    Log.info { "Queue '#{queue_name}' size: #{queue.size}" }
  end
end
