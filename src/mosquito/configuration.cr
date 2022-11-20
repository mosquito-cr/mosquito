module Mosquito
  class_getter configuration = Configuration.new

  def self.configure(&block) : Nil
    yield configuration
  end

  class Configuration
    property redis_url : String?

    property idle_wait : Time::Span = 100.milliseconds
    property successful_job_ttl : Int32 = 1
    property failed_job_ttl : Int32 = 86400

    @[Deprecated("cron scheduling is now handled automatically")]
    property run_cron_scheduler : Bool = true
    property run_from : Array(String) = [] of String
    property backend : Mosquito::Backend.class = Mosquito::RedisBackend

    property validated = false

    def idle_wait=(time_span : Float)
      @idle_wait = time_span.seconds
    end

    def validate
      return if @validated
      @validated = true

      if redis_url.nil?
        message = <<-error
        Mosquito cannot start because the redis connection string hasn't been provided.

        For example, in your application config:

        Mosquito.configure do |settings|
          settings.redis_url = (ENV["REDIS_TLS_URL"]? || ENV["REDIS_URL"]? || "redis://localhost:6379")
        end

        See Also: https://github.com/mosquito-cr/mosquito#connecting-to-redis
        error

        raise message
      end
    end

  end
end
