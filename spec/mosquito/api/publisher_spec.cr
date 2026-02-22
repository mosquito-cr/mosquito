require "../../spec_helper"

describe Mosquito::Api::Publisher do
  let(executor_pipeline) { Channel(Tuple(Mosquito::JobRun, Mosquito::Queue)).new }
  let(idle_notifier) { Channel(Bool).new }
  let(job) { QueuedTestJob.new }
  let(job_run : Mosquito::JobRun) { job.enqueue }

  let(overseer) { MockOverseer.new }
  let(executor) { MockExecutor.new overseer.as(Mosquito::Runners::Overseer) }
  let(api) { Mosquito::Api::Executor.new executor.object_id.to_s }
  let(observer) { Mosquito::Observability::Executor.new executor }

  it "doesn't publish events when metrics are disabled" do
    job_run.store
    job_run.build_job

    PubSub.instance.clear
    published_messages = eavesdrop do
      Mosquito.temp_config(publish_metrics: false) do
        observer.execute job_run, job.class.queue do
        end
      end
    end

    assert_equal 0, published_messages.size
  end
end
