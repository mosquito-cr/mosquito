require "./queue"

module Mosquito::LeakyBucket
  # When rate limited, this will cause the job order to be shuffled.  A proper
  # leaky bucket would be implemented at the Queue level, but mosquito doesn't
  # currently have the ability to instantiate mutiple types of queues. See
  # Runner#fetch_queues.
  #
  # When rate limited, the mosquito runner will verbosely complain about the
  # many job failures.
  module Limiter
    DEFAULT_DRIP_RATE = 10.milliseconds
    DEFAULT_BUCKET_SIZE = 15

    module ClassMethods
      def leaky_bucket(*,
          drip_rate : Time::Span = DEFAULT_DRIP_RATE,
          bucket_size : Int32 = DEFAULT_BUCKET_SIZE
      )
        @@drip_rate = drip_rate
        @@bucket_size = bucket_size
      end
    end

    macro included
      extend ClassMethods

      @@drip_rate = DEFAULT_DRIP_RATE
      @@bucket_size = DEFAULT_BUCKET_SIZE

      before do
        retry_later unless will_drip?
      end

      after do
        drip! if executed?
      end
    end

    def rescheduleable? : Bool
      rate_limited?
    end

    def reschedule_interval(retry_count : Int32) : Time::Span
      if rate_limited?
        time_to_drip
      else
        super
      end
    end

    def rate_limited? : Bool
      ! will_drip?
    end

    def enqueue : Task
      if can_enqueue?
        super
      else
        raise "No room left in bucket"
      end
    end

    def can_enqueue? : Bool
      self.class.queue.size < @@bucket_size
    end


    def will_drip? : Bool
      time_to_drip <= 0.seconds
    end

    @_time_to_drip : Time::Span? = nil
    def time_to_drip : Time::Span
      @_time_to_drip ||= begin
        last_drip = metadata["last_drip"]?
        return 0.seconds if last_drip.nil?
        last_drip = Time.unix_ms last_drip.to_i64
        last_drip + @@drip_rate - Time.utc
      end
    end

    def drip!
      now = Time.utc.to_unix_ms
      last_drip = metadata["last_drip"]?

      if last_drip
        return unless last_drip.to_i64 < now
      end

      metadata["last_drip"] = now.to_s
    end
  end
end
