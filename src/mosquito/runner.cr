require "colorize"

module Mosquito
  class Runner
    Log = ::Log.for self

    # Should mosquito continue working?
    class_property keep_running : Bool = true

    def self.start
      Log.notice { "Mosquito is buzzing..." }
      instance.run
    end

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
