require "minitest"
require "minitest/focus"

require "timecop"
Timecop.safe_mode = true

ENV["REDIS_URL"] = "redis://127.0.0.1:6379/3"

require "../src/mosquito"
require "./helpers/*"

Mosquito::Redis.instance.flushall

require "minitest/autorun"
