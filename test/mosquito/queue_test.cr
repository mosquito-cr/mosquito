require "../test_helper"

describe Queue do
  let(:name) { "test" }

  @throttled_queue : Mosquito::Queue?
  let(:throttled_queue) do
    Mosquito::Queue.new(name).tap do |queue|
      queue.flush
      Mosquito::Redis.instance.store_hash(queue.config_q, {"limit" => "0", "period" => "0", "executed" => "0", "next_batch" => "0", "last_executed" => "0"})
      queue
    end
  end

  @test_queue : Mosquito::Queue?
  let(:test_queue) do
    Mosquito::Queue.new(name).tap do |queue|
      queue.flush
      Mosquito::Redis.instance.store_hash(queue.config_q, {"limit" => "0", "period" => "0", "executed" => "0", "next_batch" => "0", "last_executed" => "0"})
      queue
    end
  end

  @task : Mosquito::Task?
  let(:task) do
    Mosquito::Task.new("mock_task").tap do |task|
      task.store
    end
  end

  let(:redis) { Mosquito::Redis.instance }

  it "builds redis keys for pending q" do
    assert_equal "mosquito:pending:#{name}", test_queue.pending_q
  end

  it "builds redis keys for waiting q" do
    assert_equal "mosquito:waiting:#{name}", test_queue.waiting_q
  end

  it "builds redis keys for scheduled q" do
    assert_equal "mosquito:scheduled:#{name}", test_queue.scheduled_q
  end

  it "builds redis keys for dead q" do
    assert_equal "mosquito:dead:#{name}", test_queue.dead_q
  end

  it "can enqueue a task for immediate processing" do
    test_queue.enqueue task
    waiting_tasks = redis.lrange test_queue.waiting_q, 0, -1
    assert_includes waiting_tasks, task.id
  end

  # todo: brittle test
  it "can enqueue a task with a relative time" do
    offset = 3.seconds
    timestamp = offset.from_now.to_unix_ms
    test_queue.enqueue task, in: offset
    stored_time = redis.zscore test_queue.scheduled_q, task.id

    assert_in_delta stored_time.not_nil!, timestamp, 2
  end

  it "can enqueue a task at a specific time" do
    timestamp = 3.seconds.from_now
    test_queue.enqueue task, at: timestamp
    stored_time = redis.zscore test_queue.scheduled_q, task.id
    assert_equal timestamp.to_unix_ms, stored_time.not_nil!.to_i64
  end

  it "moves a task from waiting to pending on dequeue" do
    test_queue.enqueue task
    stored_task = test_queue.dequeue

    assert_equal task.id, stored_task.not_nil!.id

    pending_tasks = redis.lrange test_queue.pending_q, 0, -1
    assert_includes pending_tasks, task.id
  end

  it "can forget about a pending task" do
    test_queue.enqueue task
    test_queue.dequeue
    pending_tasks = redis.lrange test_queue.pending_q, 0, -1
    assert_includes pending_tasks, task.id

    test_queue.forget task
    pending_tasks = redis.lrange test_queue.pending_q, 0, -1
    refute_includes pending_tasks, task.id
  end

  it "can banish a pending task, adding it to the dead q" do
    test_queue.enqueue task
    test_queue.dequeue
    pending_tasks = redis.lrange test_queue.pending_q, 0, -1
    assert_includes pending_tasks, task.id

    test_queue.banish task
    pending_tasks = redis.lrange test_queue.pending_q, 0, -1
    refute_includes pending_tasks, task.id

    dead_tasks = redis.lrange test_queue.dead_q, 0, -1
    assert_includes dead_tasks, task.id
  end

  it "dequeues tasks which have been scheduled for a time that has passed" do
    task1 = task
    task2 = Mosquito::Task.new("mock_task").tap do |task|
      task.store
    end

    past = 1.minute.ago
    future = 1.minute.from_now
    test_queue.enqueue task1, at: past
    test_queue.enqueue task2, at: future

    # check to make sure only task1 was dequeued
    overdue_tasks = test_queue.dequeue_scheduled
    assert_equal 1, overdue_tasks.size
    assert_equal task1.id, overdue_tasks.first.id

    # check to make sure task2 is still scheduled
    scheduled_tasks = redis.zrange test_queue.scheduled_q, 0, -1
    refute_includes scheduled_tasks, task1.id
    assert_includes scheduled_tasks, task2.id
  end

  describe "#rate_limited?" do
    describe "when it has not ran yet" do
      it "should not be rate_limited" do
        refute throttled_queue.rate_limited?
        assert_equal Mosquito::Redis.instance.retrieve_hash(throttled_queue.config_q), {"limit" => "0", "period" => "0", "executed" => "0", "next_batch" => "0", "last_executed" => "0"}
      end
    end

    describe "when it has less executions than limit" do
      it "should not be rate_limited" do
        time = Time.utc.to_unix

        Mosquito::Redis.instance.store_hash(throttled_queue.config_q, {"limit" => "5", "period" => "15", "executed" => "2", "next_batch" => "0", "last_executed" => "#{time}"})

        refute throttled_queue.rate_limited?
        assert_match Mosquito::Redis.instance.retrieve_hash(throttled_queue.config_q)["executed"], "2"
      end
    end

    describe "when it is at its limit" do
      it "should be rate_limited" do
        time = Time.utc.to_unix

        Mosquito::Redis.instance.store_hash(throttled_queue.config_q, {"limit" => "5", "period" => "15", "executed" => "5", "next_batch" => "#{time + 15}", "last_executed" => "#{time}"})

        assert throttled_queue.rate_limited?
        assert_match Mosquito::Redis.instance.retrieve_hash(throttled_queue.config_q)["executed"], "5"
      end
    end

    describe "when it is at its limit but execution was longer than period seconds ago" do
      it "should not be rate_limited" do
        # Simulate the queue being at its limit but the last execution was an hour ago.
        last_executed = Time.utc.to_unix - 1.hour.to_i

        Mosquito::Redis.instance.store_hash(throttled_queue.config_q, {"limit" => "5", "period" => "15", "executed" => "5", "next_batch" => "0", "last_executed" => "#{last_executed}"})

        # Should not be limited since the period is only 15 seconds.
        refute throttled_queue.rate_limited?

        # Should have its executed set back to 0
        assert_match Mosquito::Redis.instance.retrieve_hash(throttled_queue.config_q)["executed"], "0"
      end
    end
  end
end

describe "Queue class methods" do
  let(:redis) { Mosquito::Redis.instance }

  it "assembles a redis key with the mosquito prefix" do
    assert_equal "mosquito:test", Mosquito::Queue.redis_key "test"
  end

  it "can get a list of available queues" do
    # create evidence of some queues
    redis.flushdb
    redis.set "mosquito:waiting:test1", 1
    redis.set "mosquito:waiting:test2", 1
    redis.set "mosquito:scheduled:test3", 1

    assert_equal ["test1", "test2", "test3"], Mosquito::Queue.list_queues.sort
  end
end
