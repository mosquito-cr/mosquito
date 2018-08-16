require "./test_helper"

describe Queue do
  let(:name) { "test" }
  let(:test_queue) { Mosquito::Queue.new name }

  it "builds redis keys for pending q" do
    assert_equal "mosquito:pending:#{name}", test_queue.pending_q
  end

  it "builds redis keys for waiting q" do
    assert_equal "mosquito:queue:#{name}", test_queue.waiting_q
  end

  it "builds redis keys for scheduled q" do
    assert_equal "mosquito:scheduled:#{name}", test_queue.scheduled_q
  end

  it "builds redis keys for dead q" do
    assert_equal "mosquito:dead:#{name}", test_queue.dead_q
  end

  it "can enqueue a task at an interval" do
    skip
  end

  it "can enqueue a task at a specific time" do
    skip
  end

  it "moves a task from waiting to pending on dequeue" do
    skip
  end

  it "can forget about a pending task" do
    skip
  end

  it "can banish a pending task, adding it to the dead q" do
    skip
  end

  it "can dequeue a task for a specific time" do
    skip
  end
end

describe "Queue class methods" do
  it "assembles a redis key with the mosquito prefix" do
    assert_equal "mosquito:test", Mosquito::Queue.redis_key "test"
  end

  it "can get a list of available queues" do
    # create evidence of some queues
    Mosquito::Redis.instance.tap do |redis|
      redis.set "mosquito:queue:test1", 1
      redis.set "mosquito:queue:test2", 1
      redis.set "mosquito:scheduled:test3", 1
    end

    assert_equal ["test1","test2","test3"], Mosquito::Queue.list_queues
  end
end
