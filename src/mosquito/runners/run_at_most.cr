module Mosquito::Runners
  module RunAtMost
    getter execution_timestamps = {} of Symbol => Time::Span

    private def run_at_most(*, every interval, label name, &block)
      now = Time.monotonic
      last_execution = @execution_timestamps[name]? || Time::Span.new(nanoseconds: 0)
      delta = now - last_execution

      if delta >= interval
        @execution_timestamps[name] = now
        yield now
      end
    end
  end
end
