module Mosquito
  module TestJobs
    class Periodic < PeriodicJob
      def perform; end
    end

    class Queued < QueuedJob
      def perform; end
    end
  end
end
