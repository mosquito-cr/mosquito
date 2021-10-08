require "../../test_helper"

describe "Mosquito::Runner#fetch_queues" do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:redis) { Mosquito::Redis.instance }

  it "filters the list of queues when a whitelist is present" do
    redis.flushall
    redis.set "mosquito:waiting:test1", 1
    redis.set "mosquito:waiting:test2", 1
    redis.set "mosquito:waiting:test3", 1

    Mosquito.temp_config(run_from: ["test1", "test3"]) do
      runner.run :fetch_queues
    end

    assert_equal %w|test1 test3|, runner.queues.map(&.name).sort
  end
end
