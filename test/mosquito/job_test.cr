require "../test_helper"

describe Mosquito::Job do
  let(:passing_job) { PassingJob.new }
  let(:failing_job) { FailingJob.new }
  let(:not_implemented_job) { NotImplementedJob.new }

  let(:throttled_job) { ThrottledJob.new }
  let(:hooked_job) { JobWithHooks.new }

  describe "run" do
    it "captures JobFailed and marks sucess=false" do
      failing_job.run
      assert failing_job.failed?
    end

    it "sets #executed? and #succeeded?" do
      refute passing_job.executed?

      passing_job.run

      assert passing_job.executed?
      assert passing_job.succeeded?
    end

    it "emits a failure message when #fail contains a reason message" do
      clear_logs

      failing_job.run
      assert failing_job.failed?

      assert_logs_match failing_job.exception_message
    end

    it "captures and marks failure for other exceptions" do
      clear_logs

      failing_job.fail_with_exception = true
      failing_job.run
      assert failing_job.failed?

      assert_logs_match failing_job.exception_message
    end

    it "captures and marks failure for other exceptions" do
      clear_logs

      assert_nil failing_job.exception

      failing_job.fail_with_exception = true
      failing_job.run
      assert failing_job.failed?
      refute_nil failing_job.exception
    end

    it "sets success=false when #fail-ed" do
      failing_job.run
      refute failing_job.succeeded?
    end

    it "fails when no perform is implemented" do
      clear_logs

      not_implemented_job.run
      assert not_implemented_job.failed?

      assert_logs_match "No job definition found"
    end

    it "raises DoubleRun if it's already been executed" do
      passing_job.run
      assert_raises Mosquito::DoubleRun do
        passing_job.run
      end
    end
  end

  it "fetches the default queue" do
    assert_equal "passing_job", PassingJob.queue.name
  end

  it "fetches the named queue" do
    assert_equal "mosquito::nil_job", NilJob.queue.name
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
        assert_equal 4.seconds, CustomRescheduleIntervalJob.new.reschedule_interval(count)
      end
    end
  end

  describe "metadata" do
    it "returns a metadata instance" do
      assert_instance_of Mosquito::Metadata, passing_job.metadata
    end

    it "is a memoized instance" do
      one = passing_job.metadata
      two = passing_job.metadata

      assert_same one, two
    end
  end

  describe "self.metadata" do
    it "returns a metadata instance" do
      assert PassingJob.metadata.is_a?(Mosquito::Metadata)
    end

    it "is readonly" do
      metadata = PassingJob.metadata
      assert metadata.readonly?
    end
  end

  describe "self.metadata_key" do
    it "includes the class name" do
      assert_includes PassingJob.metadata_key, "passing_job"
    end
  end

  describe "before_hooks" do
    it "should execute hooks" do
      clear_logs
      hooked_job.should_fail = false
      hooked_job.run
      assert_logs_match "Before Hook Executed"
      assert_logs_match "2nd Before Hook Executed"
      assert_logs_match "Perform Executed"
    end

    it "should not exec when a before hook fails the job" do
      clear_logs
      hooked_job.should_fail = true
      hooked_job.run

      assert_logs_match "Before Hook Executed"
      assert_logs_match "2nd Before Hook Executed"
      refute_logs_match "Perform Executed"
    end
  end

  describe "after_hooks" do
    it "should execute `after` hooks" do
      clear_logs
      hooked_job.should_fail = false
      hooked_job.run
      assert_logs_match "After Hook Executed"
      assert_logs_match "2nd After Hook Executed"
      assert_logs_match "Perform Executed"
    end

    it "should run the `after` hooks even if a job fails" do
      clear_logs
      hooked_job.should_fail = true
      hooked_job.run
      assert_logs_match "After Hook Executed"
      assert_logs_match "2nd After Hook Executed"
      refute_logs_match "Perform Executed"
    end
  end
end
