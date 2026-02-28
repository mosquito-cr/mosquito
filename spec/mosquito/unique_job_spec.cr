require "../spec_helper"

describe Mosquito::UniqueJob do
  describe "first enqueue" do
    it "enqueues a job when no duplicate exists" do
      clean_slate do
        job = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job_run = job.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal [job_run.id], enqueued
      end
    end
  end

  describe "duplicate suppression" do
    it "prevents a second enqueue with the same parameters" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job_run1 = job1.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job_run2 = job2.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size
      end
    end

    it "allows enqueue with different parameters" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job1.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueTestJob.new(user_id: 2_i64, email_type: "welcome")
        job2.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 2, enqueued.size
      end
    end

    it "allows enqueue with different parameter values" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job1.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueTestJob.new(user_id: 1_i64, email_type: "reminder")
        job2.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 2, enqueued.size
      end
    end
  end

  describe "key filtering" do
    it "considers only specified key fields for uniqueness" do
      clean_slate do
        # Same user_id, different message — should be suppressed because
        # key is only [:user_id]
        job1 = UniqueWithKeyJob.new(user_id: 1_i64, message: "hello")
        job1.enqueue
        enqueued = UniqueWithKeyJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueWithKeyJob.new(user_id: 1_i64, message: "world")
        job2.enqueue
        enqueued = UniqueWithKeyJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size
      end
    end

    it "allows enqueue when key fields differ" do
      clean_slate do
        job1 = UniqueWithKeyJob.new(user_id: 1_i64, message: "hello")
        job1.enqueue
        enqueued = UniqueWithKeyJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueWithKeyJob.new(user_id: 2_i64, message: "hello")
        job2.enqueue
        enqueued = UniqueWithKeyJob.queue.backend.list_waiting
        assert_equal 2, enqueued.size
      end
    end
  end

  describe "expiration" do
    it "allows re-enqueue after the uniqueness window expires" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job_run1 = job1.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        # Manually remove the lock to simulate expiration
        lock_key = job1.uniqueness_key(job_run1)
        Mosquito.backend.unlock(lock_key, job_run1.id)

        job2 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job2.enqueue
        enqueued = UniqueTestJob.queue.backend.list_waiting
        assert_equal 2, enqueued.size
      end
    end
  end

  describe "no parameters" do
    it "works with jobs that have no parameters" do
      clean_slate do
        job1 = UniqueNoParamsJob.new
        job1.enqueue
        enqueued = UniqueNoParamsJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size

        job2 = UniqueNoParamsJob.new
        job2.enqueue
        enqueued = UniqueNoParamsJob.queue.backend.list_waiting
        assert_equal 1, enqueued.size
      end
    end
  end

  describe "delayed enqueue" do
    it "prevents duplicate delayed enqueue" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job1.enqueue(in: 5.minutes)
        scheduled = UniqueTestJob.queue.backend.list_scheduled
        assert_equal 1, scheduled.size

        job2 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job2.enqueue(in: 10.minutes)
        scheduled = UniqueTestJob.queue.backend.list_scheduled
        assert_equal 1, scheduled.size
      end
    end

    it "prevents duplicate when mixing immediate and delayed enqueue" do
      clean_slate do
        job1 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job1.enqueue
        waiting = UniqueTestJob.queue.backend.list_waiting
        assert_equal 1, waiting.size

        job2 = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
        job2.enqueue(in: 5.minutes)
        scheduled = UniqueTestJob.queue.backend.list_scheduled
        assert_equal 0, scheduled.size
      end
    end
  end

  describe "unique_duration" do
    it "returns the configured duration" do
      job = UniqueTestJob.new(user_id: 1_i64, email_type: "welcome")
      assert_equal 1.hour, job.unique_duration
    end
  end
end
