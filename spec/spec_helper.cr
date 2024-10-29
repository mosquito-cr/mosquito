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

Mosquito.configuration.backend.flush

require "minitest/autorun"
