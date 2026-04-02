require "../../spec_helper"

describe "Mosquito::RemoteConfigDequeueAdapter" do
  getter(overseer : MockOverseer) { MockOverseer.new }
  getter(queue_list : MockQueueList) { overseer.queue_list.as(MockQueueList) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  it "uses defaults when no remote config is present" do
    clean_slate do
      register QueuedTestJob
      3.times { QueuedTestJob.new.enqueue }

      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queued_test_job" => 2},
        refresh_interval: 0.seconds,
      )

      # Two dequeues should succeed.
      result1 = adapter.dequeue(queue_list)
      refute_nil result1

      result2 = adapter.dequeue(queue_list)
      refute_nil result2

      # Third should be blocked by the default limit of 2.
      result3 = adapter.dequeue(queue_list)
      assert_nil result3
    end
  end

  it "picks up remote limits from the backend" do
    clean_slate do
      register QueuedTestJob
      3.times { QueuedTestJob.new.enqueue }

      # Default allows 2, but remote overrides to 1.
      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queued_test_job" => 2},
        refresh_interval: 0.seconds,
      )

      Mosquito::RemoteConfigDequeueAdapter.store_limits({"queued_test_job" => 1})

      result1 = adapter.dequeue(queue_list)
      refute_nil result1

      # Should be blocked — remote limit is 1.
      result2 = adapter.dequeue(queue_list)
      assert_nil result2
    end
  end

  it "merges remote limits on top of defaults" do
    clean_slate do
      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queue_a" => 3, "queue_b" => 5},
        refresh_interval: 0.seconds,
      )

      # Remote only overrides queue_a and adds queue_c.
      Mosquito::RemoteConfigDequeueAdapter.store_limits({
        "queue_a" => 1,
        "queue_c" => 7,
      })

      adapter.refresh_limits

      assert_equal 1, adapter.limits["queue_a"]
      assert_equal 5, adapter.limits["queue_b"]
      assert_equal 7, adapter.limits["queue_c"]
    end
  end

  it "falls back to defaults when remote config is cleared" do
    clean_slate do
      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queue_a" => 3},
        refresh_interval: 0.seconds,
      )

      Mosquito::RemoteConfigDequeueAdapter.store_limits({"queue_a" => 1})
      adapter.refresh_limits
      assert_equal 1, adapter.limits["queue_a"]

      Mosquito::RemoteConfigDequeueAdapter.clear_limits
      adapter.refresh_limits
      assert_equal 3, adapter.limits["queue_a"]
    end
  end

  it "respects refresh_interval and does not poll on every dequeue" do
    clean_slate do
      register QueuedTestJob
      3.times { QueuedTestJob.new.enqueue }

      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queued_test_job" => 3},
        refresh_interval: 1.hour,
      )

      # First dequeue triggers the initial refresh.
      adapter.dequeue(queue_list)

      # Store a tighter limit — but it should NOT take effect
      # because the refresh interval hasn't elapsed.
      Mosquito::RemoteConfigDequeueAdapter.store_limits({"queued_test_job" => 1})

      result2 = adapter.dequeue(queue_list)
      refute_nil result2, "Expected dequeue to succeed because refresh hasn't fired"
    end
  end

  it "delegates finished_with to the inner adapter" do
    clean_slate do
      register QueuedTestJob
      2.times { QueuedTestJob.new.enqueue }

      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queued_test_job" => 1},
        refresh_interval: 0.seconds,
      )

      result1 = adapter.dequeue(queue_list)
      refute_nil result1
      assert_equal 1, adapter.active_count("queued_test_job")

      # Blocked.
      result2 = adapter.dequeue(queue_list)
      assert_nil result2

      # Signal completion.
      adapter.finished_with(result1.not_nil!.job_run, result1.not_nil!.queue)
      assert_equal 0, adapter.active_count("queued_test_job")

      # Now a dequeue should succeed again.
      result3 = adapter.dequeue(queue_list)
      refute_nil result3
    end
  end

  it "can be used via the overseer" do
    clean_slate do
      adapter = Mosquito::RemoteConfigDequeueAdapter.new(
        defaults: {"queued_test_job" => 5},
        refresh_interval: 0.seconds,
      )
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

  describe "class-level storage helpers" do
    it "round-trips limits through the backend" do
      clean_slate do
        limits = {"queue_a" => 3, "queue_b" => 7}
        Mosquito::RemoteConfigDequeueAdapter.store_limits(limits)

        retrieved = Mosquito::RemoteConfigDequeueAdapter.stored_limits
        assert_equal 3, retrieved["queue_a"]
        assert_equal 7, retrieved["queue_b"]
      end
    end

    it "returns an empty hash when no limits are stored" do
      clean_slate do
        retrieved = Mosquito::RemoteConfigDequeueAdapter.stored_limits
        assert_equal({} of String => Int32, retrieved)
      end
    end

    it "clear_limits removes stored data" do
      clean_slate do
        Mosquito::RemoteConfigDequeueAdapter.store_limits({"queue_a" => 1})
        Mosquito::RemoteConfigDequeueAdapter.clear_limits

        retrieved = Mosquito::RemoteConfigDequeueAdapter.stored_limits
        assert_equal({} of String => Int32, retrieved)
      end
    end
  end

  describe "Api integration" do
    it "reads and writes limits through the Api module" do
      clean_slate do
        Mosquito::Api.set_concurrency_limits({"queue_x" => 10})
        result = Mosquito::Api.concurrency_limits
        assert_equal 10, result["queue_x"]
      end
    end
  end
end
