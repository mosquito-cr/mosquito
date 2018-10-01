def with_fresh_redis
  Mosquito::Redis.instance.tap do |redis|
    redis.flushall
    yield
    redis.flushall
  end
end
