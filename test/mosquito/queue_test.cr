require "../test_helper"

describe Queue do
  let(:name) { "test#{rand(1000)}" }

  let(:test_queue) do
    Mosquito::Queue.new(name)
  end

  @task : Mosquito::Task?
  let(:task) do
    Mosquito::Task.new("mock_task").tap(&.store)
  end

  let(:backend) do
    Mosquito::RedisBackend.named name
  end

  it "can enqueue a task for immediate processing" do
    clean_slate do
      test_queue.enqueue task
      task_ids = backend.dump_waiting_q
      assert_includes task_ids, task.id
    end
  end

  it "can enqueue a task with a relative time" do
    Timecop.freeze(Time.utc) do
      clean_slate do
        offset = 3.seconds
        timestamp = offset.from_now.to_unix_ms
        test_queue.enqueue task, in: offset

        stored_time = backend.scheduled_task_time task
        assert_equal stored_time, timestamp.to_s
      end
    end
  end

  it "can enqueue a task at a specific time" do
    Timecop.freeze(Time.utc) do
      clean_slate do
        timestamp = 3.seconds.from_now
        test_queue.enqueue task, at: timestamp
        stored_time = backend.scheduled_task_time task
        assert_equal timestamp.to_unix_ms.to_s, stored_time
      end
    end
  end

  it "moves a task from waiting to pending on dequeue" do
    test_queue.enqueue task
    stored_task = test_queue.dequeue

    assert_equal task.id, stored_task.not_nil!.id

    pending_tasks = backend.dump_pending_q
    assert_includes pending_tasks, task.id
  end

  it "can forget about a pending task" do
    test_queue.enqueue task
    test_queue.dequeue
    pending_tasks = backend.dump_pending_q
    assert_includes pending_tasks, task.id

    test_queue.forget task
    pending_tasks = backend.dump_pending_q
    refute_includes pending_tasks, task.id
  end

  it "can banish a pending task, adding it to the dead q" do
    test_queue.enqueue task
    test_queue.dequeue
    pending_tasks = backend.dump_pending_q
    assert_includes pending_tasks, task.id

    test_queue.banish task
    pending_tasks = backend.dump_pending_q
    refute_includes pending_tasks, task.id

    dead_tasks = backend.dump_dead_q
    assert_includes dead_tasks, task.id
  end

  it "dequeues tasks which have been scheduled for a time that has passed" do
    task1 = task
    task2 = Mosquito::Task.new("mock_task").tap do |task|
      task.store
    end

    Timecop.freeze(Time.utc) do
      past = 1.minute.ago
      future = 1.minute.from_now
      test_queue.enqueue task1, at: past
      test_queue.enqueue task2, at: future
    end

    # check to make sure only task1 was dequeued
    overdue_tasks = test_queue.dequeue_scheduled
    assert_equal 1, overdue_tasks.size
    assert_equal task1.id, overdue_tasks.first.id

    # check to make sure task2 is still scheduled
    scheduled_tasks = backend.dump_scheduled_q
    refute_includes scheduled_tasks, task1.id
    assert_includes scheduled_tasks, task2.id
  end

  describe "#rate_limited?" do
    describe "when it has not ran yet" do
      it "should not be rate_limited" do
        refute test_queue.rate_limited?
        assert_equal test_queue.get_config, Mosquito::Queue.default_config
      end
    end

    describe "when it has less executions than limit" do
      it "should not be rate_limited" do
        time = Time.utc.to_unix

        Mosquito::Redis.instance.store_hash(test_queue.config_key, {"limit" => "5", "period" => "15", "executed" => "2", "next_batch" => "0", "last_executed" => "#{time}"})

        refute test_queue.rate_limited?
        assert_match test_queue.get_config["executed"], "2"
      end
    end

    describe "when it is at its limit" do
      it "should be rate_limited" do
        time = Time.utc.to_unix

        Mosquito::Redis.instance.store_hash(test_queue.config_key, {"limit" => "5", "period" => "15", "executed" => "5", "next_batch" => "#{time + 15}", "last_executed" => "#{time}"})

        assert test_queue.rate_limited?
        assert_match test_queue.get_config["executed"], "5"
      end
    end

    describe "when it is at its limit but execution was longer than period seconds ago" do
      it "should not be rate_limited" do
        # Simulate the queue being at its limit but the last execution was an hour ago.
        last_executed = Time.utc.to_unix - 1.hour.to_i

        test_queue.set_config({"limit" => "5", "period" => "15", "executed" => "5", "next_batch" => "0", "last_executed" => "#{last_executed}"})

        # Should not be limited since the period is only 15 seconds.
        refute test_queue.rate_limited?

        # Should have its executed set back to 0
        assert_match test_queue.get_config["executed"], "0"
      end
    end
  end
end
