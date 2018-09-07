require "../../test_helper"

describe "task storage" do
  let(:redis) { Mosquito::Redis.instance }

  let(:config) {
    {
      "year" => "1752",
      "name" => "the year september lost 12 days"
    }
  }

  @task : Mosquito::Task?
  let(:task) do
    Mosquito::Task.new("mock_task").tap do |task|
      task.config = config
      task.store
    end
  end

  @task_id : String?
  let(:task_id) { task.id.not_nil! }

  it "builds a redis key correctly" do
    assert_equal "mosquito:task:1", Mosquito::Task.redis_key "1"
    assert_equal "mosquito:task:#{task.id}", task.redis_key
  end

  it "can store and retrieve a task with attributes" do
    stored_task = Mosquito::Task.retrieve task_id
    if stored_task
      assert_equal config, stored_task.config
    else
      raise "Could not retrieve task"
    end
  end

  it "can delete a task" do
    task.delete
    saved_config = redis.retrieve_hash task.redis_key
    assert_empty saved_config
  end
end
