require "../../test_helper"

describe "Mosquito::Runner#idle_wait" do
  let(:runner) { Mosquito::TestableRunner.new }

  it "idles correctly" do
    runner.run :start_time

    elapsed_time = Time.measure do
      runner.run :idle
    end

    subsecond = elapsed_time.total_seconds

    assert_in_delta(Mosquito.settings.idle_wait, subsecond, delta: 0.1)
  end

  it "sets idle_wait correctly" do
    runner.idle_wait = 2.seconds

    runner.run :start_time

    elapsed_time = Time.measure do
      runner.run :idle
    end

    two_seconds = elapsed_time.total_seconds

    assert_in_delta(Mosquito.settings.idle_wait, two_seconds, delta: 0.1)
  end
end
