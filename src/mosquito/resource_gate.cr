module Mosquito
  # A ResourceGate controls whether work should be dequeued based on
  # external resource availability (GPU utilization, CPU load, network
  # bandwidth, etc.).
  #
  # Subclass `ResourceGate` and implement `#check` to test the resource.
  # The result is cached for `sample_ttl` so expensive checks (shelling
  # out to nvidia-smi, reading /sys, etc.) aren't repeated on every
  # dequeue spin.
  #
  # ## Example
  #
  # ```crystal
  # class GpuUtilizationGate < Mosquito::ResourceGate
  #   def initialize(@threshold : Float64 = 85.0)
  #     super(sample_ttl: 2.seconds)
  #   end
  #
  #   protected def check : Bool
  #     current_gpu_utilization < @threshold
  #   end
  # end
  # ```
  abstract class ResourceGate
    getter sample_ttl : Time::Span

    @last_result : Bool = true
    @last_check_at : Time = Time::UNIX_EPOCH

    def initialize(@sample_ttl : Time::Span = 2.seconds)
    end

    # Returns the cached result of `#check`, re-evaluating only after
    # `sample_ttl` has elapsed since the last check.
    def allow? : Bool
      now = Time.utc
      if now - @last_check_at >= @sample_ttl
        @last_result = check
        @last_check_at = now
      end
      @last_result
    end

    # Subclasses implement the actual resource check. Called at most
    # once per `sample_ttl` interval.
    protected abstract def check : Bool

    # Called after a job finishes, in case the gate needs to update
    # internal bookkeeping (e.g. decrement an in-flight counter).
    def released(job_run : JobRun, queue : Queue) : Nil
    end
  end
end
