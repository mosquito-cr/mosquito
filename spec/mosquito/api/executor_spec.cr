require "../../spec_helper"

describe Mosquito::Api::Executor do
  let(executor_pipeline) { Channel(Tuple(Mosquito::JobRun, Mosquito::Queue)).new }
  let(idle_notifier) { Channel(Bool).new }
  let(job_run_id) { "job_run_id" }
  let(queue_name) { "a queue" }
  let(job_run) { Mosquito::JobRun.new "job_run", Time.utc, job_run_id }
  let(queue) { Mosquito::Queue.new queue_name }

  let(executor) { MockExecutor.new executor_pipeline, idle_notifier }
  let(api) { Mosquito::Api::Executor.new executor.object_id.to_s }
  let(observer) { Mosquito::Observability::Executor.new executor }

  it "can read the current job and queue after being started" do
    observer.start job_run, queue
    assert_equal job_run_id, api.current_job
    assert_equal queue_name, api.current_job_queue
  end

  it "clears the current job and queue after being started" do
    observer.finish true
    assert api.current_job.nil?
    assert api.current_job_queue.nil?
  end

  it "returns a nil heartbeat before the executor has triggered it" do
    assert api.heartbeat.nil?
  end

  it "returns a valid heartbeat" do
    now = Time.utc
    Timecop.freeze now do
      observer.heartbeat!
    end

    # the heartbeat is stored as a unix epoch without millis
    assert_equal now.at_beginning_of_second, api.heartbeat
  end
end
