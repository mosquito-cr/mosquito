require "../test_helper"

describe Queue do
  getter(name) { "test#{rand(1000)}" }

  getter(test_queue) do
    Mosquito::Queue.new(name)
  end

  @job_run : Mosquito::JobRun?
  getter(job_run) do
    Mosquito::JobRun.new("mock_job_run").tap(&.store)
  end

  getter backend : Mosquito::Backend do
    TestHelpers.backend.named name
  end

  describe "config_key" do
    it "defaults to name" do
      name = "random_name"
      assert_equal name, Mosquito::Queue.new(name).config_key
    end
  end

  describe "flush" do
    it "purges all of the queue entries" do
      job_runs = (1..4).map do
        Mosquito::JobRun.new("mock_job_run").tap do |job_run|
          job_run.store
          test_queue.enqueue job_run
        end
      end

      assert_equal job_runs.size, test_queue.size
      test_queue.flush
      assert_equal 0, test_queue.size
    end
  end

  describe "enqueue" do
    it "can enqueue a job_run for immediate processing" do
      clean_slate do
        test_queue.enqueue job_run
        job_run_ids = backend.dump_waiting_q
        assert_includes job_run_ids, job_run.id
      end
    end

    it "can enqueue a job_run with a relative time" do
      Timecop.freeze(Time.utc) do
        clean_slate do
          offset = 3.seconds
          timestamp = offset.from_now.to_unix_ms
          test_queue.enqueue job_run, in: offset

          stored_time = backend.scheduled_job_run_time job_run
          assert_equal stored_time, timestamp.to_s
        end
      end
    end

    it "can enqueue a job_run at a specific time" do
      Timecop.freeze(Time.utc) do
        clean_slate do
          timestamp = 3.seconds.from_now
          test_queue.enqueue job_run, at: timestamp
          stored_time = backend.scheduled_job_run_time job_run
          assert_equal timestamp.to_unix_ms.to_s, stored_time
        end
      end
    end
  end

  describe "dequeue" do
    it "moves a job_run from waiting to pending on dequeue" do
      test_queue.enqueue job_run
      stored_job_run = test_queue.dequeue

      assert_equal job_run.id, stored_job_run.not_nil!.id

      pending_job_runs = backend.dump_pending_q
      assert_includes pending_job_runs, job_run.id
    end

    it "dequeues job_runs which have been scheduled for a time that has passed" do
      job_run1 = job_run
      job_run2 = Mosquito::JobRun.new("mock_job_run").tap do |job_run|
        job_run.store
      end

      Timecop.freeze(Time.utc) do
        past = 1.minute.ago
        future = 1.minute.from_now
        test_queue.enqueue job_run1, at: past
        test_queue.enqueue job_run2, at: future
      end

      # check to make sure only job_run1 was dequeued
      overdue_job_runs = test_queue.dequeue_scheduled
      assert_equal 1, overdue_job_runs.size
      assert_equal job_run1.id, overdue_job_runs.first.id

      # check to make sure job_run2 is still scheduled
      scheduled_job_runs = backend.dump_scheduled_q
      refute_includes scheduled_job_runs, job_run1.id
      assert_includes scheduled_job_runs, job_run2.id
    end
  end

  it "can forget about a pending job_run" do
    test_queue.enqueue job_run
    test_queue.dequeue
    pending_job_runs = backend.dump_pending_q
    assert_includes pending_job_runs, job_run.id

    test_queue.forget job_run
    pending_job_runs = backend.dump_pending_q
    refute_includes pending_job_runs, job_run.id
  end

  describe "banish" do
    it "can banish a pending job_run, adding it to the dead q" do
      test_queue.enqueue job_run
      test_queue.dequeue
      pending_job_runs = backend.dump_pending_q
      assert_includes pending_job_runs, job_run.id

      test_queue.banish job_run
      pending_job_runs = backend.dump_pending_q
      refute_includes pending_job_runs, job_run.id

      dead_job_runs = backend.dump_dead_q
      assert_includes dead_job_runs, job_run.id
    end
  end

end
