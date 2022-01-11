class QueuedJob < Mosquito::QueuedJob
  params count : Int32

  def perform
    count.times do |i|
      log "ohai #{i}"
    end

    # For integration testing
    metadata.increment "run_count"
  end
end

QueuedJob.new(3).enqueue
