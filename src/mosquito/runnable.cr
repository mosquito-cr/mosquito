module Mosquito
  # Runnable implements a general purpose spawn/loop which carries a state
  # enum.
  #
  # ## Managing a Runnable
  #
  # The primary purpose of Runnable is to cleanly abstract the details of
  # spawning a thread, running a loop, and shutting down when asked.
  #
  # A service which manages a Runnable might look like this:
  #
  # ```crystal
  # runnable = MyRunnable.new
  #
  # # This will spawn and return immediately.
  # runnable.start
  #
  # puts runnable.state # => State::Working
  #
  # # Some time later...
  # should_be_stopped = runnable.stop has_stopped =
  # should_be_stopped.receive
  # ```
  #
  #
  # ## Implementing a Runnable
  #
  # A runnable implementation needs to implement only two methods: #each_run
  # and #runnable_name. In addition, pre_run and post_run are available for
  # setup and teardown.
  #
  # Runnable state is managed automatically through startup and shutdown, but
  # within each_run it can be manually altered with `#state=`.
  #
  # ### Example
  #
  # ```crystal
  # class MyRunnable
  #   include Mosquito::Runnable
  #
  #   # Optional
  #   def pre_run
  #     puts "my runnable is starting"
  #   end
  #
  #   def each_run
  #     puts "my runnable is running"
  #   end
  #
  #   # Optional
  #   def post_run
  #     puts "my runnable has stopped"
  #   end
  #
  #   def runnable_name
  #     "MyRunnable"
  #   end
  # end
  # ```
  #
  # Implementation details about what work should be done in the spawned fiber
  # are placed in #each_run.
  #
  module Runnable
    enum State
      Starting
      Working
      Idle
      Stopping
      Finished
      Crashed

      def running?
        starting? || working? || idle?
      end

      # ie, not starting
      def started?
        working? || idle?
      end
    end

    # Tracks the state of this runnable.
    #
    # Initially it will be `State::Starting`. After `#run` is called it will
    # be `State::Working`.
    #
    # When `#stop` is called it will be `State::Stopping`. After `#run` finishes,
    # it will be `State::Finished`.
    #
    # It is not necessary to set this manually, but it's available to an implementation
    # if needed. See `Mosquito::Runners::Executor#state=` (source code) for an example.
    getter state : State = State::Starting

    # After #run has been called this holds a reference to the Fiber
    # which is used to check that the fiber is still running.
    getter fiber : Fiber?

    private def state=(state : State)
      @state = state
    end

    def dead? : Bool
      if fiber_ = fiber
        fiber_.dead?
      else
        false
      end
    end

    # Start the Runnable, and capture the fiber to a property.
    #
    # The spawned fiber will not return as long as state.running?.
    #
    # State can be altered internally or externally to cause it to exit
    # but the cleanest way to do that is to call #stop.
    def run
      log = Log.for(my_name)
      @fiber = spawn(name: my_name) do
        log.info { runnable_name + " is starting" }

        self.state = State::Working
        pre_run

        while state.running?
          each_run
        end

        post_run
        self.state = State::Finished
      rescue any_exception
        self.state = State::Crashed

        log.error { "crashed with #{any_exception.inspect}" }
      end
    end

    # Request that the next time the run loop cycles it should exit instead.
    # The runnable doesn't exit immediately so #stop returns a notification
    # channel.
    #
    # #stop spawns a fiber which monitors the state and sends a bool in two
    # circumstances.  It will stop waiting for the spawn to exit at 25 seconds.
    # If the spawn has actually stopped the notification channel will broadcast
    # a true, otherwise false.
    def stop : Channel(Bool) self.state = State::Stopping if state.running?
      notifier = Channel(Bool).new

      spawn do
        start = Time.utc
        while state.stopping? && (Time.utc - start) < 25.seconds
          Fiber.yield
        end
        notifier.send state.finished?

        Log.info { runnable_name + " has stopped" }
      end

      notifier
    end

    # Used to print a pretty name for logging.
    abstract def runnable_name : String

    # Implementation of what this Runnable should do on each cycle.
    #
    # Take care that @state is #running? at the end of the method
    # unless it is finished and should exit.
    abstract def each_run : Nil

    # Available to hook a one time setup before the run loop.
    def pre_run : Nil ; end

    # Available to hook any teardown logic after the run loop.
    def post_run : Nil ; end
  end
end
