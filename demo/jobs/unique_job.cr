class UniqueJob < Mosquito::QueuedJob
  include Mosquito::UniqueJob

  unique_for 1.hour, key: [:user_id]

  param user_id : Int64
  param message : String

  def perform
    log "Sending to user #{user_id}: #{message}"
    metadata.increment "run_count"
  end
end

# First enqueue — accepted
UniqueJob.new(user_id: 1_i64, message: "hello").enqueue

# Duplicate user_id — suppressed by uniqueness lock
UniqueJob.new(user_id: 1_i64, message: "hello again").enqueue

# Different user_id — accepted
UniqueJob.new(user_id: 2_i64, message: "hello").enqueue
