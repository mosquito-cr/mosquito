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

    def tick_metrics(stage : String) : Nil
      time = Time.utc

      Mosquito.backend.tap do |backend|
        daily_bucket = metrics_key({stage, "daily", time.month, time.day})
        hourly_bucket = metrics_key({stage, "hourly", time.hour})
        minutely_bucket = metrics_key({stage, "minutely", time.hour, time.minute})

        backend.increment daily_bucket, Backend.build_key(time.month, time.day)
        backend.increment hourly_bucket, Backend.build_key(time.day, time.hour)
        backend.increment minutely_bucket, Backend.build_key(time.hour, time.minute)

        backend.delete daily_bucket, in: 2.days
        backend.delete hourly_bucket, in: 24.hours
        backend.delete minutely_bucket, in: 1.hour
      end
    end

    def metrics_key(key_parts : Tuple)
      Backend.build_key "metrics", "runner"
    end
  end
end
