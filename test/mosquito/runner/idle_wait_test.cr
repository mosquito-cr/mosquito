require "../../test_helper"

describe "Mosquito::Runner#idle_wait" do
  let(:runner) { Mosquito::TestableRunner.new }

  # these both have a false failure rate of about 1 in 1000 (0.1%).
  it "idles correctly" do
    runner.run :start_time

    elapsed_time = Time.measure do
      runner.run :idle
    end

    assert_in_delta(runner.idle_wait, elapsed_time.total_seconds, delta: 0.02)
  end
end
