require "../../test_helper"

describe "Mosquito::Runner#set_start_time" do
  let(:runner) { Mosquito::TestableRunner.new }

  it "logs the start time" do
    assert_equal 0.seconds, runner.start_time
    runner.run :start_time
    refute_equal 0.seconds, runner.start_time
  end
end
