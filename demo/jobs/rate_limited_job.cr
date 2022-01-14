class RateLimitedJob < Mosquito::QueuedJob
  before do
    log self.class.rate_limit_stats
  end

  include Mosquito::RateLimiter

  throttle limit: 3, per: 10.seconds

  params count : Int32

  def perform
    log @@rate_limit_key
  end
end

15.times do
  RateLimitedJob.new(3).enqueue
end
