require "../../spec_helper"

describe Mosquito::Api::Overseer do
  let(:overseer) { MockOverseer.new }
  let(:api) { Mosquito::Api::Overseer.new(overseer.object_id.to_s) }
  let(:observer) { Observability::Overseer.new(overseer) }
  let(:executor) { MockExecutor.new(overseer.as(Mosquito::Runners::Overseer))}

  describe "publish context" do
    it "includes object_id" do
      assert_equal "overseer:#{overseer.object_id}", observer.publish_context.context
      assert_equal "mosquito:overseer:#{overseer.object_id}", observer.publish_context.originator
    end
  end

  it "allows fetching a list of executors" do
    assert_equal 1, api.executors.size
    observer.update_executor_list([executor, executor])
    assert_equal 2, api.executors.size
  end

  it "allows getting the latest heartbeat" do
    assert_nil api.last_heartbeat
    observer.heartbeat
    assert_instance_of Time, api.last_heartbeat
  end

  it "publishes the startup event" do
    eavesdrop do
      observer.starting
    end
    assert_message_received /started/
  end

  it "publishes the stopping event" do
    eavesdrop do
      observer.stopping
    end
    assert_message_received /stopped/
  end

  it "publishes the stopped event" do
    eavesdrop do
      observer.stopped
    end
    assert_message_received /exited/
  end

  it "publishes an event when an executor dies" do
    eavesdrop do
      observer.executor_died executor
    end
    assert_message_received /died/
  end

  it "publishes an event when an executor is created" do
    eavesdrop do
      observer.executor_created executor
    end
    assert_message_received /created/
  end
end
