require "../test_helper"

describe Mosquito::Runner do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:redis) { Mosquito::Redis.instance }
  let(:idle_wait) { Mosquito::Runner::IDLE_WAIT }

  it "gets a list of queues from redis" do
    # create evidence of some queues

    with_fresh_redis do
      redis.set "mosquito:queue:test1", 1
      redis.set "mosquito:queue:test2", 1
      redis.set "mosquito:scheduled:test3", 1
      runner.run :fetch_queues
    end

    assert_equal %w|test1 test2 test3|, runner.queues.map(&.name)
  end

  it "logs the start time" do
    Timecop.freeze Time.now do
      assert_equal 0, runner.start_time
      runner.run :start_time
      assert_equal Time.now.epoch, runner.start_time
    end
  end

  it "prevents throttled blocks from running too often" do
    count = 0

    2.times do
      runner.yield_once_a_second do
        count += 1
      end
    end

    assert_equal 1, count
  end

  it "allows throttled blocks to run after enough time has passed" do
    count = 0
    moment = Time.now
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

  it "idles correctly" do
    runner.run :start_time

    start = Time.now
    runner.run :idle
    finish = Time.now

    subsecond = (finish - start).milliseconds / 1000.0

    assert_in_delta(idle_wait, subsecond, delta: 0.01)
  end
end
