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

def with_idle_wait(tmp_idle_wait : Time::Span, &) : Nil
  current_idle_wait = Mosquito::Runner.idle_wait

  Mosquito::Runner.idle_wait = tmp_idle_wait

  yield

  Mosquito::Runner.idle_wait = current_idle_wait || Mosquito::Runner.idle_wait
end
