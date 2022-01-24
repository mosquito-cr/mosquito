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

def default_job_config(job)
  Mosquito::Redis.instance.store_hash(job.queue.config_q, {
    "limit" => "0",
    "period" => "0",
    "executed" => "0",
    "next_batch" => "0",
    "last_executed" => "0"
  })
end
