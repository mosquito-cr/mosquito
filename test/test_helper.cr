require "minitest"
require "minitest/focus"

require "timecop"
Timecop.safe_mode = true

require "../src/mosquito"

Mosquito.configure do |settings|
  settings.redis_url = "redis://localhost:6379/3"
end

require "./helpers/*"

Mosquito::Redis.instance.flushall

require "minitest/autorun"
