require "../../test_helper"

describe "Mosquito::Runner#idle_wait" do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:idle_wait) { Mosquito::Runner::IDLE_WAIT }

  it "idles correctly" do
    runner.run :start_time

    start = Time.local
    runner.run :idle
    finish = Time.local

    subsecond = (finish - start).milliseconds / 1000.0

    assert_in_delta(idle_wait, subsecond, delta: 0.01)
  end
end
