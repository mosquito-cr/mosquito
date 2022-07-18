require "../../test_helper"

describe "Mosquito::Runner#fetch_queues" do
  getter(runner) { Mosquito::TestableRunner.new }

  it "filters the list of queues when a whitelist is present" do
    backend = Mosquito.configuration.backend

    backend.flush
    backend.set "mosquito:waiting:test1", "key", "value"
    backend.set "mosquito:waiting:test2", "key", "value"
    backend.set "mosquito:waiting:test3", "key", "value"

    Mosquito.temp_config(run_from: ["test1", "test3"]) do
      runner.run :fetch_queues
    end

    assert_equal %w|test1 test3|, runner.queues.map(&.name).sort
  end
end
