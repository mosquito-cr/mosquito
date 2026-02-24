module Mosquito::Runners
  module RunAtMost
    getter execution_timestamps = {} of Symbol => Time::Instant

    private def run_at_most(*, every interval, label name, &block)
      now = Time.instant
      last_execution = @execution_timestamps[name]?

      if last_execution.nil? || (now - last_execution) >= interval
        @execution_timestamps[name] = now
        yield now
      end
    end
  end
end
