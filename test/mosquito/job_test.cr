require "../test_helper"

describe Mosquito::Job do
  let(:passing_job) { PassingJob.new }
  let(:failing_job) { FailingJob.new }
  let(:not_implemented_job) { NotImplementedJob.new }

  it "raises when asked if #succeeded? before execution" do
    exception = assert_raises do
      passing_job.succeeded?
    end

    assert_match /hasn't been executed/, exception.message
  end

  it "run captures JobFailed and marks sucess=false" do
    failing_job.run
    assert failing_job.failed?
  end

  it "run sets #executed? and #succeeded?" do
    refute passing_job.executed?

    passing_job.run

    assert passing_job.executed?
    assert passing_job.succeeded?
  end

  it "run captures and marks failure for other exceptions" do
    clear_logs

    failing_job.fail_with_exception = true
    failing_job.run
    assert failing_job.failed?

    assert_includes logs, failing_job.exception_message
  end

  it "marks success=false when #fail-ed" do
    failing_job.run
    refute failing_job.succeeded?
  end

  it "fails when no perform is implemented" do
    clear_logs

    not_implemented_job.run
    assert not_implemented_job.failed?

    assert_includes logs, "No job definition found"
  end

  it "raises DoubleRun if it's already been executed" do
    passing_job.run
    assert_raises Mosquito::DoubleRun do
      passing_job.run
    end
  end

  it "fetches the default queue" do
    assert_equal "passing_job", PassingJob.queue.name
  end

  it "fetches the named queue" do
    assert_equal "default", NilJob.queue.name
  end

  describe "reschedule interval" do
    it "calculates reschedule interval correctly" do
      intervals = {
        1 => 2,
        2 => 8,
        3 => 18,
        4 => 32
      }

      intervals.each do |count, delay|
        assert_equal delay.seconds, passing_job.reschedule_interval(count)
      end
    end


    it "allows overriding the reschedule interval" do
      intervals = 1..4

      intervals.each do |count|
        assert_equal 4.seconds, Mosquito::TestJobs::CustomRescheduleIntervalJob.new.reschedule_interval(count)
      end
    end
  end
end
