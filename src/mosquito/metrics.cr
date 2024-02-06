module Mosquito

  class Metrics
    Log = ::Log.for self

    module Shorthand
      def metric
        if Mosquito.configuration.send_metrics
          with Metrics.instance yield
        end
      end
    end

    property send_metrics : Bool

    def self.instance
      @@instance ||= new
    end

    def initialize
      @send_metrics = Mosquito.configuration.send_metrics
    end

  end
end
