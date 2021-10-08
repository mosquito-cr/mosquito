require "../test_helper"

describe Mosquito::Job do
  @passing_job : Mosquito::Job?
  let(:passing_job) do
    passing_job = PassingJob.new
    Mosquito::Redis.instance.store_hash(passing_job.class.queue.config_key, {"limit" => "0", "period" => "0", "executed" => "0", "next_batch" => "0", "last_executed" => "0"})
    passing_job
  end

  @throttled_job : Mosquito::Job?
  let(:throttled_job) do
    throttled_job = ThrottledJob.new
    Mosquito::Redis.instance.store_hash(throttled_job.class.queue.config_key, {"limit" => "6", "period" => "10", "executed" => "0", "next_batch" => "0", "last_executed" => "0"})
    throttled_job
  end

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

  describe "#increment" do
    it "should just increment executed if the job is not rate limited" do
      passing_job.run
      assert_equal Mosquito::Redis.instance.retrieve_hash(passing_job.class.queue.config_key), {"limit" => "0", "period" => "0", "executed" => "1", "next_batch" => "0", "last_executed" => "0"}
    end

    it "should increment executed and update last_executed when ran" do
      Timecop.freeze(Time.unix(1500000000)) do
        throttled_job.run
        assert_equal Mosquito::Redis.instance.retrieve_hash(throttled_job.class.queue.config_key), {"limit" => "6", "period" => "10", "executed" => "1", "next_batch" => "0", "last_executed" => "1500000000"}
      end
    end

    it "should reset execution count and update last_executed/next_batch when executed equals limit" do
      Mosquito::Redis.instance.store_hash(throttled_job.class.queue.config_key, {"limit" => "6", "period" => "10", "executed" => "5", "next_batch" => "0", "last_executed" => "0"})

      Timecop.freeze(Time.unix(1500000000)) do
        throttled_job.run
        assert_equal Mosquito::Redis.instance.retrieve_hash(throttled_job.class.queue.config_key), {"limit" => "6", "period" => "10", "executed" => "0", "next_batch" => "1500000010", "last_executed" => "1500000000"}
      end
    end
  end
end
