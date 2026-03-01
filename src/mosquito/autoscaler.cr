module Mosquito
  # The Autoscaler monitors constrained resources and recommends how many
  # executors the Overseer should run.
  #
  # When any monitored resource exceeds the `scale_down_threshold`, the
  # autoscaler recommends reducing executor count. When all monitored
  # resources are below the `scale_up_threshold`, it recommends increasing
  # executor count.
  #
  # ## Configuration
  #
  # ```crystal
  # autoscaler = Mosquito::Autoscaler.new(
  #   min_executors: 1,
  #   max_executors: 20,
  #   scale_up_threshold: 0.3,
  #   scale_down_threshold: 0.8,
  # )
  # autoscaler.add_monitor MyCpuMonitor.new
  # autoscaler.add_monitor MyGpuMonitor.new
  #
  # Mosquito.configure do |settings|
  #   settings.autoscaler = autoscaler
  # end
  # ```
  #
  # ## How Scaling Decisions Are Made
  #
  # On each check cycle, the autoscaler evaluates only the *active*
  # monitors — those whose resource name matches at least one constraint
  # declared by a registered job. If no jobs declare constraints, all
  # monitors are considered active.
  #
  # The highest utilization across active monitors drives the decision:
  #
  # - **Above `scale_down_threshold`**: recommend one fewer executor
  # - **Below `scale_up_threshold`**: recommend one more executor
  # - **Between thresholds**: recommend no change
  #
  # The result is always clamped between `min_executors` and `max_executors`.
  class Autoscaler
    Log = ::Log.for("mosquito.autoscaler")

    # The minimum number of executors to maintain.
    property min_executors : Int32

    # The maximum number of executors to allow.
    property max_executors : Int32

    # When the highest utilization across all active monitors falls below
    # this threshold, the autoscaler recommends adding an executor.
    property scale_up_threshold : Float64

    # When the highest utilization across any active monitor exceeds this
    # threshold, the autoscaler recommends removing an executor.
    property scale_down_threshold : Float64

    # How often the autoscaler evaluates resource utilization.
    property check_interval : Time::Span

    # Registered resource monitors, keyed by resource name.
    getter monitors : Hash(String, ResourceMonitor) = {} of String => ResourceMonitor

    def initialize(
      @min_executors : Int32 = 1,
      @max_executors : Int32 = 10,
      @scale_up_threshold : Float64 = 0.3,
      @scale_down_threshold : Float64 = 0.8,
      @check_interval : Time::Span = 5.seconds
    )
    end

    # Registers a resource monitor.
    #
    # The monitor's `#name` is used to match against job constraints
    # declared via `ResourceConstraint.constrain`.
    def add_monitor(monitor : ResourceMonitor) : Nil
      @monitors[monitor.name] = monitor
    end

    # Returns monitors whose resource name matches at least one constraint
    # declared by a registered job.
    #
    # If no jobs declare constraints, all monitors are returned.
    def active_monitors : Array(ResourceMonitor)
      constrained = ResourceConstraint.all_constraints
      return monitors.values if constrained.empty?

      monitors.values.select { |m| constrained.includes?(m.name) }
    end

    # Given the current executor count, returns the recommended count.
    #
    # Returns `current_count` unchanged when there are no active monitors
    # or when utilization is within the normal operating range.
    def recommend(current_count : Int32) : Int32
      active = active_monitors
      return current_count.clamp(min_executors, max_executors) if active.empty?

      max_utilization = active.max_of(&.utilization)

      Log.trace { "Max utilization: #{max_utilization}, current executors: #{current_count}" }

      target = if max_utilization > scale_down_threshold
        current_count - 1
      elsif max_utilization < scale_up_threshold
        current_count + 1
      else
        current_count
      end

      target.clamp(min_executors, max_executors)
    end
  end
end
