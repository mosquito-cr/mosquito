module Mosquito
  class PublishContext
    property originator : String
    property context : String

    def initialize(context : Array(String | Symbol))
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", @context
    end

    def initialize(parent : self, context : Array(String | Symbol))
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", parent.context, context
    end
  end

  class Metrics
    Log = ::Log.for self

    module Shorthand
      def metric
        if Mosquito.configuration.send_metrics
          with Metrics.instance yield
        end
      end
    end

    property send_metrics : Bool

    def self.instance
      @@instance ||= new
    end

    def initialize
      @send_metrics = Mosquito.configuration.send_metrics
    end

    def beat_heart(metadata : Metadata) : Nil
      return unless send_metrics
      Log.info { "Beating Heart" }

      # update the timestamp
      metadata["heartbeat_at"] = Time.utc.to_unix.to_s

      metadata.delete(Mosquito.configuration.heartbeat_interval * 10)
    end

    def publish(context : PublishContext, data : NamedTuple) : Nil
      Mosquito.backend.publish(
        context.originator,
        data.to_json
      )
    end

    def count(stage : Array(String | Symbol)) : Nil
      time = Time.utc

      month_key = "month=#{time.month}"
      day_key = "day=#{time.day}"
      hour_key = "hour=#{time.hour}"
      minute_key = "minute=#{time.minute}"
      second_key = "second=#{time.second}"

      Mosquito.backend.tap do |backend|
        daily_bucket = Backend.build_key :metrics, stage, :daily, month_key, day_key
        hourly_bucket = Backend.build_key :metrics, stage, :hourly, day_key, hour_key
        minutely_bucket = Backend.build_key :metrics, stage, :minutely, hour_key, minute_key
        secondly_bucket = Backend.build_key :metrics, stage, :secondly, minute_key, second_key

        backend.increment daily_bucket
        backend.increment hourly_bucket
        backend.increment minutely_bucket
        backend.increment secondly_bucket

        backend.delete daily_bucket, in: 2.days
        backend.delete hourly_bucket, in: 24.hours
        backend.delete minutely_bucket, in: 1.hour
        backend.delete secondly_bucket, in: 1.minute
      end
    end

    def record_job_duration(name : String, duration : Time::Span) : Nil
      Mosquito.backend.average_push name, duration.total_milliseconds.to_i
      Mosquito.backend.delete name, in: 30.days
    end

    def job_duration(name : String)
      Mosquito.backend.average name
    end

    def metrics_key(key_parts : Tuple)
      Backend.build_key "metrics", "runner"
    end
  end
end
