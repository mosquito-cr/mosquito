require "../../spec_helper"

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

    incrementy = ->() do
      yielder.yield_once_a_second do
        count += 1
      end
    end

    # Should increment (first call always runs)
    incrementy.call
    assert_equal 1, count

    # Should not increment (no real time has passed)
    incrementy.call
    assert_equal 1, count

    # Simulate that the last execution was over 1 second ago
    yielder.execution_timestamps[:testing] = Time.instant - 1.1.seconds

    # Should increment now
    incrementy.call
    assert_equal 2, count

    # Should not increment (called again immediately)
    incrementy.call
    assert_equal 2, count
  end
end
