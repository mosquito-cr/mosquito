require "../../test_helper"

describe "Mosquito::Runner#fetch_queues" do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:redis) { Mosquito::Redis.instance }

  it "gets a list of queues from redis" do
    with_fresh_redis do
      redis.set "mosquito:queue:test1", 1
      redis.set "mosquito:queue:test2", 1
      redis.set "mosquito:scheduled:test3", 1

      redis.set "mosquito:not_a_queue:yolo", 23

      runner.run :fetch_queues
    end

    assert_equal %w|test1 test2 test3|, runner.queues.map(&.name)
  end
end
