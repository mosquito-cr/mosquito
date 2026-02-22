require "../../spec_helper"

describe Mosquito::Job::State do
  describe "executed?" do
    it "Marks jobs as executed when they've either succeeded or failed" do
      assert Mosquito::Job::State::Succeeded.executed?
      assert Mosquito::Job::State::Failed.executed?
    end

    it "Doesn't mark jobs as executed in any other state" do
      refute Mosquito::Job::State::Initialization.executed?
      refute Mosquito::Job::State::Running.executed?
      refute Mosquito::Job::State::Aborted.executed?
      refute Mosquito::Job::State::Preempted.executed?
    end
  end
end
