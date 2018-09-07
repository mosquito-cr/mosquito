require "minitest"
require "minitest/focus"
require "minitest/autorun"

ENV["REDIS_URL"] = "redis://127.0.0.1:6379/3"

require "../mosquito"
require "./helpers/*"

Mosquito::Redis.instance.flushall
