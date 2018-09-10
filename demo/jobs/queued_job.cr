class QueuedJob < Mosquito::QueuedJob
  params count : Int32

  def perform
    count.times do
      log "ohai"
    end
  end
end

QueuedJob.new(3).enqueue
