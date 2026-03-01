require "../../spec_helper"

class AutoscaleFixedMonitor < Mosquito::ResourceMonitor
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

# A constrained job for the integration tests.
class AutoscaleConstrainedJob < Mosquito::QueuedJob
  include Mosquito::ResourceConstraint
  constrain :cpu

  include PerformanceCounter
end

describe "Overseer autoscaling integration" do
  getter(overseer : MockOverseer) { MockOverseer.new }

  describe "target_executor_count" do
    it "defaults to executor_count from configuration" do
      assert_equal overseer.executor_count, overseer.target_executor_count
    end
  end

  describe "scale up" do
    it "spawns additional executors when autoscaler recommends more" do
      clean_slate do
        # Start with 1 executor (from MockOverseer default)
        initial_count = overseer.executors.size
        assert_equal 1, initial_count

        autoscaler = Mosquito::Autoscaler.new(
          min_executors: 1,
          max_executors: 5,
          scale_up_threshold: 0.5,
        )
        monitor = AutoscaleFixedMonitor.new("cpu", 0.1)
        autoscaler.add_monitor(monitor)

        Mosquito.temp_config(autoscaler: autoscaler) do
          # Run the overseer's autoscale (via each_run or direct call)
          overseer.target_executor_count = 1
          # The autoscaler should recommend scaling up from 1 to 2
          recommended = autoscaler.recommend(overseer.executors.size)
          assert recommended > initial_count

          # Scale up by adding executors to match recommendation
          (recommended - overseer.executors.size).times do
            overseer.executors << overseer.build_executor
          end
          overseer.target_executor_count = recommended

          assert_equal 2, overseer.executors.size
          assert_equal 2, overseer.target_executor_count
        end
      end
    end
  end

  describe "scale down" do
    it "releases idle executors when autoscaler recommends fewer" do
      clean_slate do
        # Start with 3 executors
        2.times { overseer.executors << overseer.build_executor }
        assert_equal 3, overseer.executors.size

        # Mark all as idle so they can be released
        overseer.executors.each do |e|
          e.as(MockExecutor).state = Mosquito::Runnable::State::Idle
        end

        autoscaler = Mosquito::Autoscaler.new(
          min_executors: 1,
          max_executors: 5,
          scale_down_threshold: 0.7,
        )
        monitor = AutoscaleFixedMonitor.new("cpu", 0.9)
        autoscaler.add_monitor(monitor)

        recommended = autoscaler.recommend(overseer.executors.size)
        assert_equal 2, recommended

        # Simulate scale-down: release excess idle executors
        to_release = overseer.executors.size - recommended
        idle = overseer.executors.select(&.state.idle?)
        idle.first(to_release).each do |executor|
          executor.released = true
          overseer.executors.delete executor
          overseer.released_executors << executor
        end
        overseer.target_executor_count = recommended

        assert_equal 2, overseer.executors.size
        assert_equal 1, overseer.released_executors.size
        assert overseer.released_executors.first.released?
      end
    end

    it "only releases idle executors, not working ones" do
      clean_slate do
        2.times { overseer.executors << overseer.build_executor }
        assert_equal 3, overseer.executors.size

        # First executor is working, rest are idle
        overseer.executors[0].as(MockExecutor).state = Mosquito::Runnable::State::Working
        overseer.executors[1].as(MockExecutor).state = Mosquito::Runnable::State::Idle
        overseer.executors[2].as(MockExecutor).state = Mosquito::Runnable::State::Idle

        idle = overseer.executors.select(&.state.idle?)
        assert_equal 2, idle.size

        # Release 2 idle executors (scale from 3 to 1)
        idle.first(2).each do |executor|
          executor.released = true
          overseer.executors.delete executor
          overseer.released_executors << executor
        end

        assert_equal 1, overseer.executors.size
        # The remaining executor should be the working one
        assert overseer.executors.first.state.working?
      end
    end
  end

  describe "executor released flag" do
    it "defaults to false" do
      executor = overseer.executors.first
      refute executor.released?
    end

    it "can be set to true" do
      executor = overseer.executors.first
      executor.released = true
      assert executor.released?
    end
  end

  describe "check_for_deceased_runners uses target_executor_count" do
    it "respawns executors up to target_executor_count not executor_count" do
      clean_slate do
        # Set a low target
        overseer.target_executor_count = 1

        # Kill all current executors
        overseer.executors.clear

        # Run the deceased check
        overseer.check_for_deceased_runners

        # Should only respawn up to target (1), not config default
        assert_equal 1, overseer.executors.size
      end
    end
  end
end
