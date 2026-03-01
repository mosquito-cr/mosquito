require "../../spec_helper"

describe "Mosquito::Runners::Overseer#scale_executors" do
  getter(overseer : MockOverseer) { MockOverseer.new }

  describe "scaling up" do
    it "adds executors to reach the target count" do
      initial_count = overseer.executors.size
      target = initial_count + 3

      overseer.scale_executors(target)

      assert_equal target, overseer.executors.size
      assert_equal target, overseer.executor_count
    end

    it "starts newly created executors" do
      initial_count = overseer.executors.size
      target = initial_count + 2

      overseer.scale_executors(target)

      new_executors = overseer.executors[initial_count..]
      new_executors.each do |executor|
        assert executor.state.running?, "New executor should be running, got #{executor.state}"
      end
    end

    it "does not disturb existing executors" do
      existing = overseer.executors.map(&.object_id)

      overseer.scale_executors(overseer.executors.size + 2)

      existing.each do |id|
        assert overseer.executors.any? { |e| e.object_id == id },
          "Existing executor #{id} should still be present"
      end
    end

    it "logs the scaling event" do
      clear_logs
      overseer.scale_executors(overseer.executors.size + 1)
      assert_logs_match "Scaled executors"
    end
  end

  describe "scaling down" do
    it "removes executors to reach the target count" do
      # Start with 4 executors.
      overseer.scale_executors(4)
      assert_equal 4, overseer.executors.size

      overseer.scale_executors(2)
      assert_equal 2, overseer.executors.size
      assert_equal 2, overseer.executor_count
    end

    it "stops the removed executors" do
      overseer.scale_executors(3)
      all_executors = overseer.executors.dup

      overseer.scale_executors(1)

      removed = all_executors - overseer.executors
      assert_equal 2, removed.size

      removed.each do |executor|
        assert executor.state.stopping? || executor.state.finished?,
          "Removed executor should be stopping or finished, got #{executor.state}"
      end
    end
  end

  describe "no-op" do
    it "does nothing when target matches current count" do
      current = overseer.executors.size
      original_ids = overseer.executors.map(&.object_id)

      overseer.scale_executors(current)

      assert_equal current, overseer.executors.size
      assert_equal original_ids, overseer.executors.map(&.object_id)
    end
  end

  describe "validation" do
    it "raises when target is less than 1" do
      assert_raises(ArgumentError) do
        overseer.scale_executors(0)
      end
    end

    it "raises when target is negative" do
      assert_raises(ArgumentError) do
        overseer.scale_executors(-1)
      end
    end
  end

  describe "executor_count" do
    it "updates executor_count to match the target" do
      overseer.scale_executors(5)
      assert_equal 5, overseer.executor_count

      overseer.scale_executors(2)
      assert_equal 2, overseer.executor_count
    end
  end
end
