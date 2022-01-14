require "../test_helper"

describe Mosquito::QueuedJob do
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
  end
end
