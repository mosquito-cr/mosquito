require "../test_helper"

describe Mosquito::Job do
  let(:passing_job) { PassingJob.new }
  let(:failing_job) { FailingJob.new }
  let(:not_implemented_job) { NotImplementedJob.new }

  let(:throttled_job) { ThrottledJob.new }
  let(:hooked_job) { JobWithBeforeHook.new }

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

  describe "before_hooks" do
    it "should execute hooks" do
      clear_logs
      hooked_job.should_fail = false
      hooked_job.run
      assert_includes logs, "Before Hook Executed"
      assert_includes logs, "2nd Before Hook Executed"
      assert_includes logs, "Perform Executed"
    end

    it "should not exec when a before hook fails the job" do
      clear_logs
      hooked_job.should_fail = true
      hooked_job.run

      assert_includes logs, "Before Hook Executed"
      assert_includes logs, "2nd Before Hook Executed"
      refute_includes logs, "Perform Executed"
    end
  end
end
