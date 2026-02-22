require "../spec_helper"

describe Mosquito::RateLimiter do
  describe "RateLimiter.rate_limit_stats" do
    it "provides the state and configuration of the limiter" do
      clean_slate do
        stats = RateLimitedJob.rate_limit_stats
        assert stats.has_key? :interval
        assert stats.has_key? :key
        assert stats.has_key? :increment
        assert stats.has_key? :limit
        assert stats.has_key? :window_start
        assert stats.has_key? :run_count
      end
    end

    it "defaults the window_start" do
      clean_slate do
        assert_equal Time::UNIX_EPOCH, RateLimitedJob.rate_limit_stats[:window_start]

        now = Time.utc.at_beginning_of_second
        RateLimitedJob.metadata["window_start"] = now.to_unix.to_s
        assert_equal now, RateLimitedJob.rate_limit_stats[:window_start]
      end
    end

    it "defaults the run_count" do
      clean_slate do
        assert_equal 0, RateLimitedJob.rate_limit_stats[:run_count]

        run_count = 27
        RateLimitedJob.metadata["run_count"] = run_count.to_s
        assert_equal run_count, RateLimitedJob.rate_limit_stats[:run_count]
      end
    end
  end

  describe "RateLimiter.metadata" do
    it "provides an instance of the metadata store" do
      assert_instance_of Metadata, RateLimitedJob.metadata
    end
  end

  describe "RateLimiter.rate_limit_key" do
    it "provides the metadata key for this class" do
      assert_equal "mosquito:rate_limit:rate_limit", RateLimitedJob.rate_limit_key
    end
  end

  describe "job counting" do
    it "increments the count when a job is run" do
      clean_slate do
        RateLimitedJob.new.run
        count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i

        RateLimitedJob.new.run
        new_count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i
        assert_equal 1, new_count - count
      end
    end

    it "doesnt increment the count when a job is not run" do
      clean_slate do
        RateLimitedJob.new(should_fail: false).run
        count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i

        RateLimitedJob.new(should_fail: true).run
        new_count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i
        assert_equal count, new_count
      end
    end

    it "increments the count by a configurable number" do
      clean_slate do
        delta = 2
        RateLimitedJob.new.run
        count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i

        RateLimitedJob.new(increment: delta).run
        new_count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i
        assert_equal delta, new_count - count
      end
    end

    it "resets the count when the window is over" do
      clean_slate do
        metadata = RateLimitedJob.metadata
        metadata["run_count"] = "45"
        metadata["window_start"] = Time::UNIX_EPOCH.to_unix.to_s
        RateLimitedJob.new.run
        count = RateLimitedJob.metadata["run_count"]?
        assert_equal "1", count
      end
    end

    it "counts multiple jobs with the same key in the same bucket" do
      clean_slate do
        metadata = RateLimitedJob.metadata
        metadata["window_start"] = Time.utc.to_unix.to_s

        RateLimitedJob.new.run
        count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i

        SecondRateLimitedJob.new.run
        new_count = RateLimitedJob.metadata["run_count"]?.not_nil!.to_i

        assert_equal RateLimitedJob.rate_limit_key, SecondRateLimitedJob.rate_limit_key
        assert_equal 1, new_count - count
      end
    end
  end

  describe "job preempting" do
    it "doesnt prevent excution if the rate limit count is less than zero" do
      metadata = RateLimitedJob.metadata
      metadata["run_count"] = "-1"
      metadata["window_start"] = Time.utc.to_unix.to_s
      job = RateLimitedJob.new
      job.run
      assert job.executed?
    end

    it "prevents a job from executing when the limit is reached" do
      metadata = RateLimitedJob.metadata
      metadata["run_count"] = Int32::MAX.to_s
      metadata["window_start"] = Time.utc.to_unix.to_s
      job = RateLimitedJob.new
      job.run
      refute job.executed?
      assert job.preempted?
    end

    it "allows a job to execute when the limit hasn't been reached" do
      metadata = RateLimitedJob.metadata
      metadata["window_start"] = Time.utc.to_unix.to_s
      metadata["run_count"] = "3"
      job = RateLimitedJob.new
      job.run
      assert job.executed?
    end

    it "allows a job to execute when the limit has been reached but the window is over" do
      metadata = RateLimitedJob.metadata
      metadata["run_count"] = Int32::MAX.to_s
      metadata["window_start"] = Time::UNIX_EPOCH.to_unix.to_s
      job = RateLimitedJob.new
      job.run
      assert job.executed?
    end
  end
end
