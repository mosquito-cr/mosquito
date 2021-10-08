require "../../test_helper"

describe "Mosquito::Runner#enqueue_delayed_tasks" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job)      { Mosquito::TestJobs::Queued.new }
  getter(runner)        { Mosquito::TestableRunner.new }
  getter(enqueue_time)  { Time.utc }
  getter(backend)       { queue.backend }

  it "enqueues a delayed task when it's ready", focus: true do
    clean_slate do
      Mosquito::Base.register_job_mapping queue.name, Mosquito::TestJobs::Queued

      task_id = ""
      Timecop.freeze enqueue_time do |t|
        task = test_job.enqueue in: 3.seconds
        task_id = task.id
      end

      runner.run :fetch_queues

      run_time = enqueue_time + 3.seconds

      Timecop.freeze run_time do |t|
        runner.run :enqueue
      end

      queued_tasks = queue.backend.dump_waiting_q
      assert_includes queued_tasks, task_id

      last_task = queued_tasks.last
      task_metadata = queue.backend.retrieve Task.config_key(last_task)

      assert_equal queue.name, task_metadata["type"]?
    end
  end

  it "doesn't enqueue tasks that arent ready yet" do
    vanilla do |redis|
      enqueue_task

      check_time = enqueue_time + 2.999.seconds

      Timecop.freeze check_time do |t|
        runner.run :enqueue
      end

      queued_tasks = redis.lrange "mosquito:waiting:#{queue_name}", 0, -1
      assert_equal 0, queued_tasks.size
    end
  end
end
