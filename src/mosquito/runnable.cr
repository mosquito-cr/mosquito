require "wait_group"

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
  # wg = WaitGroup.new(1)
  # runnable.stop(wg)
  # wg.wait
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

    # Signaled when the run loop exits (finished or crashed).
    private getter done = Channel(Nil).new

    getter my_name : String {
      "#{self.class.name.underscore.gsub("::", ".")}.#{self.object_id}"
    }

    private getter log : ::Log { Log.for runnable_name }

    private def state=(new_state : State)
      # If the state is currently stopping, don't go back to idle.
      if @state.stopping? && new_state.idle?
        log.trace { "Ignoring state change to #{new_state} because state=stopping." }
        return
      end

      @state = new_state
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
    #
    # By default, the run loop is spawned in a new fiber and control
    # returns immediately. Pass `spawn: false` to run the loop directly
    # in the current fiber (blocking until finished).
    def run(*, spawn spawn_fiber = true)
      if spawn_fiber
        @fiber = spawn(name: runnable_name) do
          run_loop
        end
      else
        run_loop
      end
    end

    private def run_loop
      log.info { "starting" }

      self.state = State::Working
      pre_run

      while state.running?
        each_run
      end

      post_run
      self.state = State::Finished
      log.info { "stopped" }
    rescue any_exception
      self.state = State::Crashed

      log.error { "crashed with #{any_exception.inspect}" }
    ensure
      done.close
    end

    # Request that the next time the run loop cycles it should exit instead.
    # The runnable doesn't exit immediately so #stop spawns a fiber to
    # monitor the state transition.
    #
    # Returns the `WaitGroup`, which will be decremented when the
    # runnable has finished. This enables `runnable.stop.wait`.
    #
    # If a `WaitGroup` is provided, it will be decremented when the
    # runnable has finished. This is useful when stopping multiple
    # runnables and waiting for all of them to finish.
    #
    # Calling stop on a runnable that has already finished or crashed is a
    # no-op (the wait_group is signaled immediately).
    def stop(wait_group : WaitGroup = WaitGroup.new(1)) : WaitGroup
      unless state.running? || state.stopping?
        wait_group.done
        return wait_group
      end

      self.state = State::Stopping if state.running?

      spawn do
        done.receive?
        wait_group.done
      end

      wait_group
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
