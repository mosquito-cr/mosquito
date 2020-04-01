require "../../test_helper"

describe "Mosquito::Runner#idle_wait" do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:idle_wait) { Mosquito::Runner.idle_wait }

  it "idles correctly" do
    runner.run :start_time

    elapsed_time = Time.measure do
      runner.run :idle
    end

    subsecond = elapsed_time.total_seconds

    assert_in_delta(idle_wait, subsecond, delta: 0.01)
  end

  it "sets idle_wait correctly" do
    with_idle_wait(2.seconds) do
      runner.run :start_time

      elapsed_time = Time.measure do
        runner.run :idle
      end

      two_seconds = elapsed_time.total_seconds

      assert_in_delta(idle_wait, two_seconds, delta: 2)
    end
  end
end
