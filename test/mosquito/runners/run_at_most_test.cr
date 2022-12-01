require "../../test_helper"

class RunsAtMostMock
  include Mosquito::Runners::RunAtMost

  def yield_once_a_second(&block)
    run_at_most every: 1.second, label: :testing do |t|
      yield
    end
  end
end

describe "Mosquito::yielder#run_at_most" do
  getter(yielder) { RunsAtMostMock.new }

  it "prevents throttled blocks from running too often" do
    count = 0

    2.times do
      yielder.yield_once_a_second do
        count += 1
      end
    end

    assert_equal 1, count
  end

  it "allows throttled blocks to run only after enough time has passed" do
    count = 0
    moment = Time.utc
    yielder
    incrementy = ->() do
      yielder.yield_once_a_second do
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
    moment += 1.1.seconds
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
