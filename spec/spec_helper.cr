require "minitest"
require "minitest/focus"

require "log"
Log.setup :fatal

require "timecop"
Timecop.safe_mode = true

require "../src/mosquito"
Mosquito.configure do |settings|
  settings.connection_string = ENV["REDIS_URL"]? || "redis://localhost:6379/3"
  settings.publish_metrics = true
end

require "./helpers/*"
class Minitest::Test
  include PubSub::Helpers
end

Mosquito.configuration.backend.flush

require "minitest/autorun"
