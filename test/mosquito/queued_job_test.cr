require "../test_helper"

describe Mosquito::QueuedJob do
  let(:runner) { Mosquito::TestableRunner.new }

  describe "parameters" do
    it "can be passed in" do
      clear_logs
      EchoJob.new("quack").perform
      assert_includes logs, "quack"
    end

    it "can have a boolean false passed as a parameter (and it's not assumed to be a nil)" do
      clear_logs
      JobWithBeforeHook.new(false).perform
      assert_includes logs, "Perform Executed"
    end

    it "can be omitted" do
      vanilla do
        Mosquito::Base.register_job_mapping "job_with_no_params", JobWithNoParams

        clear_logs
        job = JobWithNoParams.new
        default_job_config job.class
        job.enqueue

        runner.run :fetch_queues
        runner.run :run
        assert_includes logs, "no param job performed"
      end
    end
  end
end
