require "habitat"

require "./external_classes"
require "./mosquito/*"

module Mosquito
  # The previous redis connection initialization method would:
  # - init with the env var if present
  # - otherwise init without a connection string, which means a default connection to localhost:6379
  #
  # cf https://github.com/stefanwille/crystal-redis/blob/009e35fa40bbd518798afcc32c397402c6c6acb2/src/redis.cr#L95
  #
  # Unfortunately, even after you've taken the appropriate action, this message will still show up if the environment variable exists.
  def Mosquito.default_redis_url
    if ENV["REDIS_URL"]?
      Log.warn {
        <<-error_message
        Configuring the Mosquito redis connection via environment variable is deprecated as of 2020-11.

        The functionality will be removed in a minor version bump, 0.10.0.

        The Redis url is now configured explicitly. To retain your current behavior, simply add this to your Mosquito runner before `Mosquito::Runner.start`:

        Mosquito.configure do |settings|
          settings.redis_url = ENV["REDIS_URL"]
        end

        See Also: https://github.com/robacarp/mosquito#connecting-to-redis

        error_message
      }
    end

    (ENV["REDIS_URL"]? || "redis://localhost:6379")
  end

  Habitat.create do
    setting redis_url : String = Mosquito.default_redis_url
    setting idle_wait : Float64 = 0.1
    setting successful_job_ttl : Int32 = 1
    setting failed_job_ttl : Int32 = 86400
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

      For example, in your job runner:

      Mosquito.configure do |settings|
        settings.redis_url = "redis://localhost:6379"
      end

      See Also: https://github.com/robacarp/mosquito#connecting-to-redis
      error

      raise message
    end

    # just in case
    Habitat.raise_if_missing_settings!
  end
end
