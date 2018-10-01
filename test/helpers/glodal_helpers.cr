def vanilla
  Mosquito::Base.bare_mapping do
    with_fresh_redis do |redis|
      yield redis
    end
  end
end

def with_fresh_redis
  Mosquito::Redis.instance.tap do |redis|
    redis.flushall
    yield redis
  end
end
