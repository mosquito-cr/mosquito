require "./test_helper"

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

    assert logs.includes? failing_job.exception_message
  end

  it "marks success=false when #fail-ed" do
    failing_job.run
    refute failing_job.succeeded?
  end

  it "fails when no perform is implemented" do
    clear_logs

    not_implemented_job.run
    assert not_implemented_job.failed?

    assert logs.includes? "No job definition found"
  end

  it "raises DoubleRun if it's already been executed" do
    passing_job.run
    assert_raises Mosquito::DoubleRun do
      passing_job.run
    end
  end
end
