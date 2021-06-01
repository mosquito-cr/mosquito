require "../../test_helper"

describe "Mosquito::Runner#enqueue_periodic_tasks" do
  let(:runner) { Mosquito::TestableRunner.new }

  it "enqueues a scheduled task" do
    Mosquito::Base.bare_mapping do
      with_fresh_redis do |redis|
        queue_name = "mosquito::test_jobs::periodic"
        Mosquito::Base.register_job_mapping queue_name, Mosquito::TestJobs::Periodic
        Mosquito::Base.register_job_interval Mosquito::TestJobs::Periodic, interval: 1.second

        enqueue_time = Time.utc.to_unix_ms
        runner.run :enqueue

        queued_tasks = redis.lrange "mosquito:waiting:#{queue_name}", 0, -1
        last_task = queued_tasks.last
        task_metadata = redis.retrieve_hash "mosquito:task:#{last_task}"

        assert_equal queue_name, task_metadata["type"]?
        assert_in_delta enqueue_time, task_metadata["enqueue_time"], 1.0
      end
    end
  end

  it "doesn't enqueue periodic tasks when disabled" do
    Mosquito::Base.bare_mapping do
      with_fresh_redis do |redis|
        queue_name = "mosquito::test_jobs::periodic"
        Mosquito::Base.register_job_mapping queue_name, Mosquito::TestJobs::Periodic
        Mosquito::Base.register_job_interval Mosquito::TestJobs::Periodic, interval: 1.second

        Mosquito.temp_config(run_cron_scheduler: false) do
          runner.run :enqueue
        end

        queued_tasks = redis.lrange "mosquito:waiting:#{queue_name}", 0, -1
        assert queued_tasks.size == 0
      end
    end
  end
end
