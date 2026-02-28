require "minitest"
require "minitest/focus"

require "log"
Log.setup :fatal

require "timecop"
Timecop.safe_mode = true

require "../src/mosquito"
Mosquito.configure do |settings|
  settings.backend_connection_string = testing_redis_url
  settings.publish_metrics = true
end

require "./helpers/*"
class Minitest::Test
  include PubSub::Helpers
end

Mosquito.configuration.backend.flush

require "minitest/autorun"
