require "colorize"

module Mosquito
  class Runner
    Log = ::Log.for self

    # Should mosquito continue working?
    class_property keep_running : Bool = true

    # Start the mosquito runner.
    #
    # If spin = true (default) the function will not return until the runner is
    # shut down.  Otherwise it will return immediately.
    #
    def self.start(spin = true) Log.notice { "Mosquito is buzzing..." }
      instance.run

      while spin && @@keep_running
        sleep 1
      end
    end

    # Request the mosquito runner stop. The runner will not abort the current job
    # but it will not start any new jobs.
    def self.stop
      Log.notice { "Mosquito is shutting down..." }
      self.keep_running = false
      instance.stop
    end

    private def self.instance : self
      @@instance ||= new
    end

    def initialize
      Mosquito.configuration.validate
      @overseer = Runners::Overseer.new
    end

    def run
      spawn do
        @overseer.run
      end
    end

    def stop
      @overseer.stop
    end
  end
end
