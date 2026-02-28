module Mosquito
  class_getter configuration = Configuration.new

  def self.configure(&block) : Nil
    yield configuration
  end

  class Configuration
    property idle_wait : Time::Span = 100.milliseconds
    property successful_job_ttl : Int32 = 1.minute.total_seconds.to_i
    property failed_job_ttl : Int32 = 86400

    property use_distributed_lock : Bool = true

    property executor_count : Int32 = ENV.fetch("MOSQUITO_EXECUTOR_COUNT", "6").to_i

    property run_from : Array(String) = [] of String
    property global_prefix : String? = nil
    property backend : Mosquito::Backend = Mosquito::RedisBackend.new

    property dequeue_adapter : Mosquito::DequeueAdapter = Mosquito::ShuffleDequeueAdapter.new

    property publish_metrics : Bool = false

    # How often a mosquito runner should emit a heartbeat metric.
    property heartbeat_interval : Time::Span = 20.seconds

    # How long an overseer can go without a heartbeat before it is
    # considered dead and its pending jobs are recovered.
    property dead_overseer_threshold : Time::Span = 100.seconds

    property validated = false

    def backend_connection
      backend.connection
    end

    def backend_connection_string
      backend.connection_string
    end

    def backend_connection_string=(value : String)
      backend.connection_string = value
    end

    def idle_wait=(time_span : Float)
      @idle_wait = time_span.seconds
    end

    def validate
      return if @validated
      @validated = true

      unless backend.valid_configuration?
        message = <<-error
        Mosquito cannot start because no backend connection has been provided.

        For example, in your application config:

        Mosquito.configure do |settings|
          settings.backend_connection_string = (ENV["REDIS_TLS_URL"]? || ENV["REDIS_URL"]? || "redis://localhost:6379")
        end

        See Also: https://github.com/mosquito-cr/mosquito#connecting-to-redis
        error

        raise message
      end
    end

    def metrics? : Bool
      publish_metrics
    end
  end
end
