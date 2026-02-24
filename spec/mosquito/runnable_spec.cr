require "../spec_helper"

class Namespace::ConcreteRunnable
  include Mosquito::Runnable

  getter first_run_notifier = Channel(Bool).new
  getter first_run = true
  property state : Mosquito::Runnable::State

  # Testing wedge which calls: run, waits for a run to happen, and then calls stop.
  def test_run : Nil
    run
    first_run_notifier.receive
    wg = WaitGroup.new(1)
    stop(wg)
    wg.wait
  end

  def runnable_name : String
    "concrete_runnable"
  end

  def each_run : Nil
    if first_run
      @first_run = false
      first_run_notifier.send true
    end
    Fiber.yield
  end

  def stop(wait_group : WaitGroup? = nil)
    first_run_notifier.close
    super(wait_group)
  end
end

describe Mosquito::Runnable do
  let(:runnable) { Namespace::ConcreteRunnable.new }

  it "builds a my_name" do
    assert_equal "namespace.concrete_runnable.#{runnable.object_id}", runnable.my_name
  end

  describe "run" do
    it "should log a startup message" do
      clear_logs
      runnable.test_run
      assert_logs_match "mosquito.concrete_runnable", "starting"
    end

    it "should log a finished message" do
      clear_logs
      runnable.test_run
      assert_logs_match "mosquito.concrete_runnable", "stopped"
    end
  end

  describe "stop" do
    it "should set the stopping flag" do
      runnable.state = Mosquito::Runnable::State::Working
      runnable.stop
      assert_equal Mosquito::Runnable::State::Stopping, runnable.state
    end

    it "should set the finished flag" do
      runnable.test_run
      assert_equal Mosquito::Runnable::State::Finished, runnable.state
    end
  end
end
