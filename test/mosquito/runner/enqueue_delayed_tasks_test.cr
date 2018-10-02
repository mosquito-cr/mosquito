require "../../test_helper"

describe "Mosquito::Runner#enqueue_delayed_tasks" do
  let(:runner) { Mosquito::TestableRunner.new }
  let(:queue_name) { "mosquito::test_jobs::queued" }

  @enqueue_time : Time?
  def enqueue_time
    @enqueue_time ||= Time.now
  end

  def enqueue_task
    Mosquito::Base.register_job_mapping queue_name, Mosquito::TestJobs::Queued

    Timecop.freeze enqueue_time do |t|
      Mosquito::TestJobs::Queued.new.enqueue in: 3.seconds
    end

    runner.run :fetch_queues
  end

  it "enqueues a delayed task when it's ready" do
    vanilla do |redis|
      enqueue_task

      run_time = enqueue_time + 3.seconds

      Timecop.freeze run_time do |t|
        runner.run :enqueue
      end

      queued_tasks = redis.lrange "mosquito:queue:#{queue_name}", 0, -1
      last_task = queued_tasks.last
      task_metadata = redis.retrieve_hash "mosquito:task:#{last_task}"

      assert_equal queue_name, task_metadata["type"]?
    end
  end

  it "doesn't enqueue tasks that arent ready yet" do
    vanilla do |redis|
      enqueue_task

      check_time = enqueue_time + 2.999.seconds

      Timecop.freeze check_time do |t|
        runner.run :enqueue
      end

      queued_tasks = redis.lrange "mosquito:queue:#{queue_name}", 0, -1
      assert_equal 0, queued_tasks.size
    end
  end

  it "wont execute more than it should" do
    skip
  end
end
