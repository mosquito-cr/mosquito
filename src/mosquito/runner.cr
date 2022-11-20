require "colorize"

module Mosquito
  class Runner
    Log = ::Log.for self

    # Should mosquito continue working?
    class_property keep_running : Bool = true

    def self.start
      instance = new
      Log.notice { "Mosquito is buzzing..." }

      while @@keep_running
        instance.run
      end
    end

    def self.stop
      Log.notice { "Mosquito is shutting down..." }
      @@keep_running = false
    end

    def initialize
      Mosquito.configuration.validate
      @bacon = Bacon.new
    end

    def run
      @bacon.run
    end
  end
end
