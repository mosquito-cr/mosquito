class QueuedJob < Mosquito::QueuedJob
  params count : Int32

  def perform
    count.times do |i|
      log "ohai #{i}"
    end

    # For integration testing
    Mosquito::Redis.instance.incr self.class.name.underscore
  end
end

QueuedJob.new(3).enqueue
