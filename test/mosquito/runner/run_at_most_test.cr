require "../../test_helper"

describe "Mosquito::Runner#run_at_most" do
  let(:runner) { Mosquito::TestableRunner.new }

  it "prevents throttled blocks from running too often" do
    count = 0

    2.times do
      runner.yield_once_a_second do
        count += 1
      end
    end

    assert_equal 1, count
  end

  it "allows throttled blocks to run only after enough time has passed" do
    count = 0
    moment = Time.utc
    runner
    incrementy = ->() do
      runner.yield_once_a_second do
        count += 1
      end
    end

    # Should increment
    Timecop.freeze moment do |time|
      incrementy.call
    end

    # Should not increment
    # Move ahead 0.999 seconds
    Timecop.freeze(moment + 999.milliseconds) do |time|
      incrementy.call
    end

    assert_equal 1, count

    # Should increment
    # Move ahead the rest of the second
    moment += 1.second
    Timecop.freeze(moment) do |time|
      incrementy.call
    end

    assert_equal 2, count

    # Should not increment
    # Try again and it shouldn't increment
    Timecop.freeze(moment) do |time|
      incrementy.call
    end

    assert_equal 2, count
  end
end
