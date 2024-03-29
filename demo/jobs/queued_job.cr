class QueuedJob < Mosquito::QueuedJob
  param count : Int32

  queue_name :demo_queue

  def perform
    count.times do |i|
      log "ohai #{i}"
    end

    # For integration testing
    metadata.increment "run_count"
  end
end

QueuedJob.new(3).enqueue
