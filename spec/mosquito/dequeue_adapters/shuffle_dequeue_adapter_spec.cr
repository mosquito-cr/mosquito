require "../../spec_helper"

describe "Mosquito::ShuffleDequeueAdapter" do
  getter(overseer : MockOverseer) { MockOverseer.new }
  getter(queue_list : MockQueueList) { overseer.queue_list.as(MockQueueList) }
  getter(executor : MockExecutor) { overseer.executors.first.as(MockExecutor) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  it "is the default adapter" do
    assert_instance_of Mosquito::ShuffleDequeueAdapter, Mosquito.configuration.dequeue_adapter
  end

  it "dequeues a job from the queue list" do
    clean_slate do
      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      adapter = Mosquito::ShuffleDequeueAdapter.new
      result = adapter.dequeue(queue_list)

      refute_nil result
      if result
        actual_job_run, queue = result
        assert_equal expected_job_run, actual_job_run
        assert_equal QueuedTestJob.queue, queue
      end
    end
  end

  it "returns nil when no jobs are available" do
    clean_slate do
      register QueuedTestJob

      adapter = Mosquito::ShuffleDequeueAdapter.new
      result = adapter.dequeue(queue_list)
      assert_nil result
    end
  end

  describe "custom adapter" do
    it "can be swapped on the overseer" do
      clean_slate do
        null_adapter = NullDequeueAdapter.new
        overseer.dequeue_adapter = null_adapter

        register QueuedTestJob
        QueuedTestJob.new.enqueue

        result = overseer.dequeue_job?
        assert_nil result
        assert_equal 1, null_adapter.dequeue_count
      end
    end

    it "receives the queue list when dequeuing" do
      clean_slate do
        spy_adapter = SpyDequeueAdapter.new
        overseer.dequeue_adapter = spy_adapter

        register QueuedTestJob
        queue_list.queues << Mosquito::Queue.new("extra_queue")

        overseer.dequeue_job?

        assert_includes spy_adapter.checked_queues, "queued_test_job"
        assert_includes spy_adapter.checked_queues, "extra_queue"
      end
    end
  end

  describe "overseer integration" do
    it "dequeue_job? delegates to the adapter" do
      clean_slate do
        register QueuedTestJob
        expected_job_run = QueuedTestJob.new.enqueue

        result = overseer.dequeue_job?
        refute_nil result
        if result
          actual_job_run, queue = result
          assert_equal expected_job_run, actual_job_run
        end
      end
    end
  end
end
