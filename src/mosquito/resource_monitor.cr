module Mosquito
  # A ResourceMonitor provides real-time utilization data for a bounded
  # resource (e.g., CPU, GPU, network bandwidth).
  #
  # Subclass `ResourceMonitor` and implement `#name` and `#utilization`
  # to create a monitor for a specific resource:
  #
  # ```crystal
  # class CpuMonitor < Mosquito::ResourceMonitor
  #   def name : String
  #     "cpu"
  #   end
  #
  #   def utilization : Float64
  #     # Read CPU usage from /proc/stat or similar
  #     0.65
  #   end
  # end
  # ```
  #
  # Register monitors with the `Autoscaler`:
  #
  # ```crystal
  # autoscaler = Mosquito::Autoscaler.new
  # autoscaler.add_monitor CpuMonitor.new
  #
  # Mosquito.configure do |settings|
  #   settings.autoscaler = autoscaler
  # end
  # ```
  abstract class ResourceMonitor
    # The name of the resource being monitored.
    #
    # This should match the symbol used in `ResourceConstraint.constrain`.
    # For example, a GPU monitor should return `"gpu"` to match
    # `constrain :gpu`.
    abstract def name : String

    # The current utilization of this resource, as a value between
    # `0.0` and `1.0`.
    #
    # - `0.0` means the resource is completely idle.
    # - `1.0` means the resource is fully saturated.
    #
    # The `Autoscaler` uses this value to make scaling decisions.
    abstract def utilization : Float64
  end
end
