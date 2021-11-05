require "../test_helper"

describe Mosquito::PeriodicTask do
  getter interval : Time::Span = 2.minutes

  it "tries to execute but fails before the interval has passed" do
    now = Time.utc
    task = PeriodicTask.new TestJobs::Periodic, interval
    task.last_executed_at = now

    Timecop.freeze(now + 1.minute) do
      task.try_to_execute
      assert_equal now, task.last_executed_at
    end
  end

  it "executes" do
    now = Time.utc
    task = PeriodicTask.new TestJobs::Periodic, interval
    task.last_executed_at = now

    Timecop.freeze(now + interval) do
      task.try_to_execute
      assert_equal now + interval, task.last_executed_at
    end
  end
end
