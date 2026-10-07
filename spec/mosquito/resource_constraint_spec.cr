require "../spec_helper"

class GpuConstrainedJob < Mosquito::QueuedJob
  include Mosquito::ResourceConstraint
  constrain :gpu

  def perform
  end
end

class MultiConstrainedJob < Mosquito::QueuedJob
  include Mosquito::ResourceConstraint
  constrain :cpu, :network

  def perform
  end
end

class UnconstrainedJob < Mosquito::QueuedJob
  def perform
  end
end

describe Mosquito::ResourceConstraint do
  describe ".constrain" do
    it "registers a single resource constraint on a job" do
      assert_equal ["gpu"], GpuConstrainedJob.resource_constraints
    end

    it "registers multiple resource constraints on a job" do
      constraints = MultiConstrainedJob.resource_constraints
      assert_includes constraints, "cpu"
      assert_includes constraints, "network"
      assert_equal 2, constraints.size
    end
  end

  describe ".registry" do
    it "maps job names to their constraints" do
      registry = Mosquito::ResourceConstraint.registry
      assert_equal ["gpu"], registry["gpu_constrained_job"]
      assert_includes registry["multi_constrained_job"], "cpu"
      assert_includes registry["multi_constrained_job"], "network"
    end

    it "does not include unconstrained jobs" do
      registry = Mosquito::ResourceConstraint.registry
      refute registry.has_key?("unconstrained_job")
    end
  end

  describe ".all_constraints" do
    it "returns the set of all unique resource names" do
      all = Mosquito::ResourceConstraint.all_constraints
      assert_includes all, "gpu"
      assert_includes all, "cpu"
      assert_includes all, "network"
    end
  end
end
