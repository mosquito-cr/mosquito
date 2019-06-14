require "../../test_helper"

describe "Mosquito::Runner#set_start_time" do
  let(:runner) { Mosquito::TestableRunner.new }

  it "logs the start time" do
    Timecop.freeze Time.utc do
      assert_equal 0, runner.start_time
      runner.run :start_time
      assert_equal Time.utc.to_unix, runner.start_time
    end
  end
end
