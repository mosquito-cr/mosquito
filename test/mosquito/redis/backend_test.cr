require "../../test_helper"

describe Mosquito::RedisBackend do
  let(:redis) { Mosquito::Redis.instance }
  let(:name) { "test" }

  getter(backend : Mosquito::Backend) {
    Mosquito::RedisBackend.named(name)
  }

  it "can get a list of available queues" do
    # create evidence of some queues
    redis.flushall
    redis.set "mosquito:waiting:test1", 1
    redis.set "mosquito:waiting:test2", 1
    redis.set "mosquito:scheduled:test3", 1

    assert_equal ["test1", "test2", "test3"], Mosquito::RedisBackend.list_queues.sort
  end

  it "builds redis keys for pending q" do
    assert_equal "mosquito:pending:#{name}", backend.pending_q
  end

  it "builds redis keys for waiting q" do
    assert_equal "mosquito:waiting:#{name}", backend.waiting_q
  end

  it "builds redis keys for scheduled q" do
    assert_equal "mosquito:scheduled:#{name}", backend.scheduled_q
  end

  it "builds redis keys for dead q" do
    assert_equal "mosquito:dead:#{name}", backend.dead_q
  end
end
