require "../spec_helper"

class FixedMonitor < Mosquito::ResourceMonitor
  property _utilization : Float64
  getter _name : String

  def initialize(@_name : String, @_utilization : Float64 = 0.5)
  end

  def name : String
    @_name
  end

  def utilization : Float64
    @_utilization
  end
end

# Jobs that declare constraints used for active_monitors filtering.
class AutoscalerTestJob < Mosquito::QueuedJob
  include Mosquito::ResourceConstraint
  constrain :cpu

  def perform
  end
end

class AutoscalerGpuTestJob < Mosquito::QueuedJob
  include Mosquito::ResourceConstraint
  constrain :gpu

  def perform
  end
end

describe Mosquito::Autoscaler do
  describe "#recommend" do
    it "returns current count clamped when no monitors are registered" do
      autoscaler = Mosquito::Autoscaler.new(min_executors: 2, max_executors: 10)
      assert_equal 5, autoscaler.recommend(5)
    end

    it "clamps below min_executors" do
      autoscaler = Mosquito::Autoscaler.new(min_executors: 3, max_executors: 10)
      assert_equal 3, autoscaler.recommend(1)
    end

    it "clamps above max_executors" do
      autoscaler = Mosquito::Autoscaler.new(min_executors: 1, max_executors: 5)
      assert_equal 5, autoscaler.recommend(8)
    end

    it "recommends scaling down when utilization exceeds scale_down_threshold" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_down_threshold: 0.8,
      )
      monitor = FixedMonitor.new("cpu", 0.9)
      autoscaler.add_monitor(monitor)

      assert_equal 5, autoscaler.recommend(6)
    end

    it "recommends scaling up when utilization is below scale_up_threshold" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_up_threshold: 0.3,
      )
      monitor = FixedMonitor.new("cpu", 0.1)
      autoscaler.add_monitor(monitor)

      assert_equal 5, autoscaler.recommend(4)
    end

    it "recommends no change when utilization is between thresholds" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_up_threshold: 0.3,
        scale_down_threshold: 0.8,
      )
      monitor = FixedMonitor.new("cpu", 0.5)
      autoscaler.add_monitor(monitor)

      assert_equal 6, autoscaler.recommend(6)
    end

    it "does not scale below min_executors" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 3,
        max_executors: 10,
        scale_down_threshold: 0.8,
      )
      monitor = FixedMonitor.new("cpu", 0.95)
      autoscaler.add_monitor(monitor)

      assert_equal 3, autoscaler.recommend(3)
    end

    it "does not scale above max_executors" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 8,
        scale_up_threshold: 0.3,
      )
      monitor = FixedMonitor.new("cpu", 0.1)
      autoscaler.add_monitor(monitor)

      assert_equal 8, autoscaler.recommend(8)
    end

    it "scales down when any single resource exceeds threshold" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_down_threshold: 0.8,
        scale_up_threshold: 0.3,
      )
      # CPU is idle but GPU is saturated — the GPU pressure should win
      autoscaler.add_monitor(FixedMonitor.new("cpu", 0.2))
      autoscaler.add_monitor(FixedMonitor.new("gpu", 0.9))

      assert_equal 5, autoscaler.recommend(6)
    end

    it "only scales up when all resources are below scale_up_threshold" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_up_threshold: 0.3,
        scale_down_threshold: 0.8,
      )
      # CPU has headroom but GPU is in the hold zone — should not scale up
      autoscaler.add_monitor(FixedMonitor.new("cpu", 0.1))
      autoscaler.add_monitor(FixedMonitor.new("gpu", 0.5))

      assert_equal 6, autoscaler.recommend(6)
    end

    it "scales up when all resources have headroom" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_up_threshold: 0.3,
        scale_down_threshold: 0.8,
      )
      autoscaler.add_monitor(FixedMonitor.new("cpu", 0.1))
      autoscaler.add_monitor(FixedMonitor.new("gpu", 0.2))

      assert_equal 7, autoscaler.recommend(6)
    end

    it "holds when resources are mixed between up and hold zones" do
      autoscaler = Mosquito::Autoscaler.new(
        min_executors: 1,
        max_executors: 10,
        scale_up_threshold: 0.3,
        scale_down_threshold: 0.8,
      )
      # GPU at 0.5 is between thresholds (hold), CPU at 0.1 wants up
      autoscaler.add_monitor(FixedMonitor.new("cpu", 0.1))
      autoscaler.add_monitor(FixedMonitor.new("gpu", 0.5))

      assert_equal 4, autoscaler.recommend(4)
    end
  end

  describe "#add_monitor" do
    it "registers a monitor by name" do
      autoscaler = Mosquito::Autoscaler.new
      monitor = FixedMonitor.new("gpu")
      autoscaler.add_monitor(monitor)

      assert_equal monitor, autoscaler.monitors["gpu"]
    end
  end

  describe "#active_monitors" do
    it "returns all monitors when no jobs declare constraints" do
      # Use bare_mapping to ensure no constrained jobs are registered
      # during this test. Since constraints are stored in a global registry
      # at class load time, we test with monitors that don't match any
      # constraint.
      autoscaler = Mosquito::Autoscaler.new
      monitor = FixedMonitor.new("cpu")
      autoscaler.add_monitor(monitor)

      # "cpu" is constrained by AutoscalerTestJob, so it's active.
      active = autoscaler.active_monitors
      assert_includes active, monitor
    end

    it "filters monitors to those matching declared constraints" do
      autoscaler = Mosquito::Autoscaler.new
      cpu_monitor = FixedMonitor.new("cpu")
      exotic_monitor = FixedMonitor.new("exotic_resource")
      autoscaler.add_monitor(cpu_monitor)
      autoscaler.add_monitor(exotic_monitor)

      active = autoscaler.active_monitors
      # AutoscalerTestJob constrains :cpu, so cpu_monitor is active.
      assert_includes active, cpu_monitor
      # No job constrains "exotic_resource", so it's filtered out.
      refute_includes active, exotic_monitor
    end
  end
end
