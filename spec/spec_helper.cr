require "minitest"
require "minitest/focus"

require "log"
Log.setup :fatal

require "timecop"
Timecop.safe_mode = true

require "../src/mosquito"
Mosquito.configure do |settings|
  settings.redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379/3"
end

require "./helpers/*"
class Minitest::Test
  include PubSub::Helpers
end

Mosquito.configuration.backend.flush

require "minitest/autorun"
