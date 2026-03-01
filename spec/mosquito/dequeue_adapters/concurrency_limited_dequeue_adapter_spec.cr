require "../../spec_helper"

describe "Mosquito::ConcurrencyLimitedDequeueAdapter" do
  getter(overseer : MockOverseer) { MockOverseer.new }
  getter(queue_list : MockQueueList) { overseer.queue_list.as(MockQueueList) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  it "dequeues a job when under the limit" do
    clean_slate do
      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 3,
      })

      result = adapter.dequeue(queue_list)
      refute_nil result
      if result
        assert_equal expected_job_run, result.job_run
        assert_equal QueuedTestJob.queue, result.queue
      end
    end
  end

  it "returns nil when no jobs are available" do
    clean_slate do
      register QueuedTestJob

      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 3,
      })

      result = adapter.dequeue(queue_list)
      assert_nil result
    end
  end

  it "skips a queue that has reached its concurrency limit" do
    clean_slate do
      register QueuedTestJob
      3.times { QueuedTestJob.new.enqueue }

      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 2,
      })

      # Dequeue twice — should succeed and fill the limit.
      result1 = adapter.dequeue(queue_list)
      refute_nil result1
      assert_equal 1, adapter.active_count("queued_test_job")

      result2 = adapter.dequeue(queue_list)
      refute_nil result2
      assert_equal 2, adapter.active_count("queued_test_job")

      # Third dequeue should be blocked by the limit.
      result3 = adapter.dequeue(queue_list)
      assert_nil result3
    end
  end

  it "allows dequeue again after finished_with" do
    clean_slate do
      register QueuedTestJob
      3.times { QueuedTestJob.new.enqueue }

      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 1,
      })

      # Fill the single slot.
      result1 = adapter.dequeue(queue_list)
      refute_nil result1
      assert_equal 1, adapter.active_count("queued_test_job")

      # Blocked.
      result2 = adapter.dequeue(queue_list)
      assert_nil result2

      # Signal that the job finished.
      adapter.finished_with(result1.not_nil!.job_run, result1.not_nil!.queue)
      assert_equal 0, adapter.active_count("queued_test_job")

      # Now dequeue should work again.
      result3 = adapter.dequeue(queue_list)
      refute_nil result3
    end
  end

  it "does not limit queues not in the limits table" do
    clean_slate do
      register QueuedTestJob
      5.times { QueuedTestJob.new.enqueue }

      # No limit configured for queued_test_job.
      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "other_queue" => 1,
      })

      # Should dequeue all 5 without blocking.
      5.times do |i|
        result = adapter.dequeue(queue_list)
        refute_nil result, "Expected dequeue ##{i + 1} to succeed"
      end
    end
  end

  it "enforces independent limits across multiple queues" do
    clean_slate do
      register QueuedTestJob
      register EchoJob
      3.times { QueuedTestJob.new.enqueue }
      3.times { EchoJob.new(text: "hello").enqueue }

      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 1,
        "io_queue"        => 2,
      })

      # Saturate queued_test_job (limit 1).
      # Because of shuffle we may get either queue first, so keep
      # dequeuing until the counters match the limits.
      results = [] of Mosquito::WorkUnit
      6.times do
        if r = adapter.dequeue(queue_list)
          results << r
        end
      end

      assert_equal 1, adapter.active_count("queued_test_job")
      assert_equal 2, adapter.active_count("io_queue")
      assert_equal 3, results.size
    end
  end

  it "finished_with does not go below zero" do
    adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
      "queued_test_job" => 3,
    })

    job_run = Mosquito::JobRun.new("queued_test_job")
    queue = Mosquito::Queue.new("queued_test_job")
    adapter.finished_with(job_run, queue)
    assert_equal 0, adapter.active_count("queued_test_job")
  end

  it "can be used via the overseer" do
    clean_slate do
      adapter = Mosquito::ConcurrencyLimitedDequeueAdapter.new({
        "queued_test_job" => 5,
      })
      overseer.dequeue_adapter = adapter

      register QueuedTestJob
      expected_job_run = QueuedTestJob.new.enqueue

      result = overseer.dequeue_job?
      refute_nil result
      if result
        assert_equal expected_job_run, result.job_run
      end
    end
  end
end
