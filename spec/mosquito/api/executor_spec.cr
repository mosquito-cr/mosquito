require "../../spec_helper"

describe Mosquito::Api::Executor do
  let(executor_pipeline) { Channel(Tuple(Mosquito::JobRun, Mosquito::Queue)).new }
  let(idle_notifier) { Channel(Bool).new }
  let(job) { QueuedTestJob.new }
  let(job_run : Mosquito::JobRun) { job.enqueue }

  let(executor) { MockExecutor.new executor_pipeline, idle_notifier }
  let(api) { Mosquito::Api::Executor.new executor.object_id.to_s }
  let(observer) { Mosquito::Observability::Executor.new executor }

  it "can read the current job and queue after being started, and clears it after" do
    Mosquito::Base.register_job_mapping job.class.name.underscore, job.class
    job_run.store
    job_run.build_job

    observer.execute job_run, job.class.queue do
      assert_equal job_run.id, api.current_job
      assert_equal job.class.queue.name, api.current_job_queue
    end

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

  it "publishes job started/finished events" do
    job_run.store
    job_run.build_job

    eavesdrop do
      observer.execute job_run, job.class.queue do
      end
    end

    assert_message_received /job-started/
    assert_message_received /job-finished/
  end

  it "measures and records average job duration" do
    job_run.store
    job_run.build_job

    # 100x the sleep duration below
    Timecop.scale(100) do
      observer.execute job_run, job.class.queue do
        sleep 0.01.seconds
      end
    end

    average_key = observer.average_key(job_run.type)
    average = Mosquito.backend.average(average_key)
    Mosquito.backend.delete average_key
    # assert that something > 0 comes back from the average.
    # backend tests cover calculating the average itself.
    assert average > 0
  end
end
