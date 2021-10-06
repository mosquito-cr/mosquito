require "habitat"

require "./external_classes"
require "./mosquito/*"

module Mosquito
  Habitat.create do
    setting redis_url : String
    setting idle_wait : Float64 = 0.1
    setting successful_job_ttl : Int32 = 1
    setting failed_job_ttl : Int32 = 86400

    setting run_cron_scheduler : Bool = true
    setting run_from : Array(String) = [] of String
    setting backend : Mosquito::Backend = Mosquito::RedisBackend.new
  end

  class HabitatSettings
    def self.idle_wait=(time_span : Time::Span)
      @@idle_wait = time_span.total_seconds
    end
  end

  @@settings_validated = false

  def self.validate_settings
    return if @@settings_validated
    @@settings_validated = true

    if settings.redis_url?.nil?
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

  def self.backend
    settings.backend
  end
end
