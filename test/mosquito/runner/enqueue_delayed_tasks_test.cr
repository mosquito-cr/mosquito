require "../../test_helper"

describe "Mosquito::Runner#enqueue_delayed_tasks" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job)      { Mosquito::TestJobs::Queued.new }
  getter(runner)        { Mosquito::TestableRunner.new }
  getter(enqueue_time)  { Time.utc }
  getter(backend)       { queue.backend }

  def enqueue_task : Task
    Mosquito::Base.register_job_mapping queue.name, Mosquito::TestJobs::Queued

    task = Task.new "blah"

    Timecop.freeze enqueue_time do |t|
      task = test_job.enqueue in: 3.seconds
    end

    assert_includes queue.backend.dump_scheduled_q, task.id
    runner.run :fetch_queues
    task
  end

  it "enqueues a delayed task when it's ready" do
    clean_slate do
      task = enqueue_task
      run_time = enqueue_time + 3.seconds

      Timecop.freeze run_time do |t|
        runner.run :enqueue
      end

      queued_tasks = queue.backend.dump_waiting_q
      assert_includes queued_tasks, task.id

      last_task = queued_tasks.last
      task_metadata = queue.backend.retrieve Task.config_key(last_task)

      assert_equal queue.name, task_metadata["type"]?
    end
  end

  it "doesn't enqueue tasks that arent ready yet" do
    clean_slate do
      task = enqueue_task

      check_time = enqueue_time + 2.999.seconds

      Timecop.freeze check_time do |t|
        runner.run :enqueue
      end

      queued_tasks = queue.backend.dump_waiting_q

      # does not deschedule and enqueue anything
      assert_equal 0, queued_tasks.size
    end
  end
end
