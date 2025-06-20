require "../../spec_helper"

describe Mosquito::Api::Overseer do
  let(:overseer) { MockOverseer.new }
  let(:api) { Mosquito::Api::Overseer.new(overseer.object_id.to_s) }
  let(:observer) { Observability::Overseer.new(overseer) }
  let(:executor) { MockExecutor.new(
    Channel(Tuple(Mosquito::JobRun, Mosquito::Queue)).new,
    Channel(Bool).new
  ) }

  it "allows fetching a list of executors" do
    assert_equal overseer.executor_count, api.executors.size
    observer.update_executor_list([executor])
    assert_equal 1, api.executors.size
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
    assert_message_received /stopping/
  end

  it "publishes the stopped event" do
    eavesdrop do
      observer.stopped
    end
    assert_message_received /stopped/
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
