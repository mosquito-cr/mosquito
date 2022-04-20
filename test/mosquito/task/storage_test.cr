require "../../test_helper"

describe "task storage" do
  getter backend : Mosquito::Backend = Mosquito.backend.named("testing")

  getter config = {
    "year" => "1752",
    "name" => "the year september lost 12 days"
  }

  getter task : Mosquito::Task do
    Mosquito::Task.new("mock_task").tap do |task|
      task.config = config
      task.store
    end
  end

  it "builds the backend key correctly" do
    assert_equal "mosquito:task:1", Mosquito::Task.config_key "1"
    assert_equal "mosquito:task:#{task.id}", task.config_key
  end

  it "can store and retrieve a task with attributes" do
    stored_task = Mosquito::Task.retrieve task.id
    if stored_task
      assert_equal config, stored_task.config
    else
      flunk "Could not retrieve task"
    end
  end

  it "stores tasks in the backend" do
    stored_task = backend.retrieve Mosquito::Task.config_key(task.id)
    stored_config = stored_task.reject! %w|type enqueue_time retry_count|
    assert_equal config, stored_config
  end

  it "can delete a task" do
    task.delete
    saved_config = Mosquito.backend.retrieve task.config_key
    assert_empty saved_config
  end

  it "can set a timed delete on a task" do
    ttl = 10
    task.delete(in: ttl)
    set_ttl = backend.expires_in task.config_key
    assert_equal ttl, set_ttl
  end

  it "can reload a task" do
    task.reload
  end
end
