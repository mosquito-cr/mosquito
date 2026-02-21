require "colorize"

module Mosquito
  # This singleton class serves as a shorthand for starting and managing an Overseer.
  #
  # A minimal usage of Mosquito::Runner is:
  #
  # ```
  # require "mosquito"
  #
  # # When the process receives sigint, it'll notify the overseer to shut down gracefully.
  # trap("INT") do
  #   Mosquito::Runner.stop(wait: true)
  # end
  #
  # # Starts the overseer, and holds the thread captive.
  # Mosquito::Runner.start
  # ```
  #
  # If for some reason you want to manage an overseer or group of overseers yourself, Mosquito::Runner can be omitted entirely:
  #
  # ```crystal
  # require "mosquito"
  #
  # mosquito = Mosquito::Overseer.new
  #
  # # Spawns a mosquito managed fiber and returns immediately
  # mosquito.run
  #
  # trap "INT" do
  #   wg = WaitGroup.new(1)
  #   mosquito.stop(wg)
  #   wg.wait
  # end
  # ```
  class Runner
    Log = ::Log.for self

    # Start the mosquito runner.
    #
    # If spin = true (default) the function will not return until the runner is
    # shut down.  Otherwise it will return immediately.
    #
    def self.start(spin = true)
      Log.notice { "Mosquito is buzzing..." }
      instance.run

      while spin && keep_running
        sleep 1.second
      end
    end

    # :nodoc:
    def self.keep_running : Bool
      instance.state.starting? || instance.state.running? || instance.state.stopping?
    end

    # Request the mosquito runner stop. The runner will not abort the current job
    # but it will not start any new jobs.
    #
    # See `Mosquito::Runnable#stop`.
    def self.stop(wait = false)
      Log.notice { "Mosquito is shutting down..." }

      if wait
        wg = WaitGroup.new(1)
        instance.stop(wg)
        wg.wait
      else
        instance.stop
      end
    end

    private def self.instance : self
      @@instance ||= new
    end

    # :nodoc:
    delegate run, stop, state, to: @overseer

    # :nodoc:
    delegate running?, to: @overseer.state

    # :nodoc:
    getter overseer : Runners::Overseer

    # :nodoc:
    def initialize
      Mosquito.configuration.validate
      @overseer = Runners::Overseer.new
    end
  end
end
