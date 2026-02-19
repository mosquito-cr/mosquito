require "../../spec_helper"

describe "Mosquito::WeightedDequeueAdapter" do
  getter(overseer : MockOverseer) { MockOverseer.new }
  getter(queue_list : MockQueueList) { overseer.queue_list.as(MockQueueList) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  it "dequeues a job from a weighted queue" do
    clean_slate do
      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      adapter = Mosquito::WeightedDequeueAdapter.new({
        "queued_test_job" => 5,
      })

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

      adapter = Mosquito::WeightedDequeueAdapter.new({
        "queued_test_job" => 3,
      })

      result = adapter.dequeue(queue_list)
      assert_nil result
    end
  end

  it "assigns default weight of 1 to unconfigured queues" do
    clean_slate do
      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      # No weight configured for queued_test_job — defaults to 1.
      adapter = Mosquito::WeightedDequeueAdapter.new({
        "other_queue" => 10,
      })

      result = adapter.dequeue(queue_list)
      refute_nil result
      if result
        actual_job_run, _ = result
        assert_equal expected_job_run, actual_job_run
      end
    end
  end

  it "higher-weight queues are dequeued more often" do
    clean_slate do
      register QueuedTestJob
      register EchoJob

      adapter = Mosquito::WeightedDequeueAdapter.new({
        "queued_test_job" => 10,
        "io_queue"        => 1,
      })

      # Enqueue enough jobs that neither queue drains during the sample.
      200.times { QueuedTestJob.new.enqueue }
      200.times { EchoJob.new(text: "hello").enqueue }

      dequeue_counts = Hash(String, Int32).new(0)

      # Sample 50 dequeues — well within the 200 available per queue.
      50.times do
        result = adapter.dequeue(queue_list)
        if result
          _, queue = result
          dequeue_counts[queue.name] = dequeue_counts[queue.name] + 1
        end
      end

      # With weights 10:1, the high-weight queue should be dequeued
      # significantly more often over a 50-dequeue sample.
      heavy_count = dequeue_counts.fetch("queued_test_job", 0)
      light_count = dequeue_counts.fetch("io_queue", 0)
      assert heavy_count > light_count, "Expected queued_test_job (#{heavy_count}) to be dequeued more than io_queue (#{light_count})"
    end
  end

  it "can be used via the overseer" do
    clean_slate do
      adapter = Mosquito::WeightedDequeueAdapter.new({
        "queued_test_job" => 5,
      })
      overseer.dequeue_adapter = adapter

      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      result = overseer.dequeue_job?
      refute_nil result
      if result
        actual_job_run, _ = result
        assert_equal expected_job_run, actual_job_run
      end
    end
  end
end
