require "../resource_gate"

module Mosquito
  # A gate that samples a metric via a callback and compares it against
  # a threshold.
  #
  # ## Example
  #
  # ```crystal
  # gate = Mosquito::ThresholdGate.new(
  #   threshold: 85.0,
  #   sample_ttl: 2.seconds
  # ) { `nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits`.strip.to_f }
  # ```
  class ThresholdGate < ResourceGate
    getter threshold : Float64

    @sampler : -> Float64

    def initialize(@threshold : Float64, sample_ttl : Time::Span = 2.seconds, &sampler : -> Float64)
      super(sample_ttl: sample_ttl)
      @sampler = sampler
    end

    protected def check : Bool
      @sampler.call < @threshold
    end
  end
end
