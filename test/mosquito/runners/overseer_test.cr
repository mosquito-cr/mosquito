require "../../test_helper"

describe "Mosquito::Runners::Overseer" do
  getter(queue_list) { MockQueueList.new }
  getter(coordinator) { MockCoordinator.new queue_list }
  getter(executor) { MockExecutor.new queue_list }

  getter(overseer : MockOverseer) {
    MockOverseer.new.tap do |o|
      o.queue_list = queue_list
      o.coordinator = coordinator
      o.executor = executor
    end
  }

  describe "tick" do
    it "waits the proper amount of time between cycles" do
      clean_slate do
        tick_time = Time.measure do
          overseer.tick
        end

        assert_in_epsilon(
          overseer.idle_wait.total_seconds,
          tick_time.total_seconds,
          epsilon: 0.02
        )
      end
    end
  end

  describe "run" do
    it "should log a startup message" do
      overseer.keep_running = false
      clear_logs
      overseer.run
      assert_logs_match "clocking in."
    end

    it "should log a finished message" do
      overseer.keep_running = false
      clear_logs
      overseer.run
      assert_logs_match "finished for now"
    end
  end

  describe "stop" do
    it "should log a stop message" do
      clear_logs
      overseer.stop
      assert_logs_match "is done after this job."
    end

    it "should set the stop flag" do
      overseer.stop
      assert_equal false, overseer.keep_running
    end
  end

  describe "worker_id" do
    it "should return a unique id" do
      one = Mosquito::Runners::Overseer.new
      two = Mosquito::Runners::Overseer.new

      refute_equal one.worker_id, two.worker_id
    end
  end
end
