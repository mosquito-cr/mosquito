module Mosquito
  # The Autoscaler monitors constrained resources and recommends how many
  # executors the Overseer should run.
  #
  # When any monitored resource exceeds the `scale_down_threshold`, the
  # autoscaler recommends reducing executor count. Scaling up only happens
  # when **every** monitored resource is below the `scale_up_threshold`.
  #
  # This per-resource evaluation ensures that mixed workloads are handled
  # correctly. For example, if GPU is saturated but CPU is idle, the
  # autoscaler scales down to protect the GPU rather than scaling up
  # because the CPU has headroom.
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
  # Each active monitor casts an independent vote:
  #
  # - **Above `scale_down_threshold`**: votes to scale down
  # - **Below `scale_up_threshold`**: votes to scale up
  # - **Between thresholds**: votes to hold
  #
  # The votes are combined conservatively:
  #
  # - If **any** monitor votes to scale down, the recommendation is to
  #   scale down (resource pressure takes priority).
  # - If **all** monitors vote to scale up, the recommendation is to
  #   scale up (every resource has headroom).
  # - Otherwise, no change.
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
    # Each active monitor votes independently based on its utilization:
    # - above `scale_down_threshold` → vote down
    # - below `scale_up_threshold` → vote up
    # - between thresholds → vote hold
    #
    # Any "down" vote wins (resource pressure is the priority). Only
    # unanimous "up" votes result in scaling up. Otherwise, hold.
    def recommend(current_count : Int32) : Int32
      active = active_monitors
      return current_count.clamp(min_executors, max_executors) if active.empty?

      any_down = false
      all_up = true

      active.each do |monitor|
        utilization = monitor.utilization
        Log.trace { "#{monitor.name}: utilization=#{utilization}" }

        if utilization > scale_down_threshold
          any_down = true
          # No need to check further — any down vote is decisive.
          break
        end

        unless utilization < scale_up_threshold
          all_up = false
        end
      end

      target = if any_down
        current_count - 1
      elsif all_up
        current_count + 1
      else
        current_count
      end

      target.clamp(min_executors, max_executors)
    end
  end
end
