class LeakyBucketJob < Mosquito::QueuedJob
  include Mosquito::LeakyBucket::Limiter

  leaky_bucket(drip_rate: 1.second, bucket_size: 10)

  def perform
    log "drip"
  end
end

spawn do
  loop do
    3.times do
      LeakyBucketJob.new.enqueue
    end
    sleep 4.seconds
  end
end
