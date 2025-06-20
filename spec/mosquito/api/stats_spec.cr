require "../../spec_helper"

describe Mosquito::Api::GlobalStats do
  describe "#total_jobs" do
    it "calculates total jobs across all queues" do
      clean_slate do
        # Create test queues with jobs
        backend1 = TestHelpers.backend.named("test_queue_1")
        backend1.enqueue(create_job_run)
        backend1.enqueue(create_job_run)

        backend2 = TestHelpers.backend.named("test_queue_2")
        backend2.enqueue(create_job_run)

        stats = Mosquito::Api::GlobalStats.new
        assert_equal 3, stats.total_jobs
      end
    end
  end

  describe "#active_overseers" do
    it "counts active workers correctly" do
      clean_slate do
        # Register some overseers
        Mosquito.backend.register_overseer("overseer1")
        Mosquito.backend.register_overseer("overseer2")

        stats = Mosquito::Api::GlobalStats.new
        assert_equal 2, stats.active_overseers
      end
    end
  end

  describe "#to_h" do
    it "provides correct health statistics hash" do
      clean_slate do
        stats = Mosquito::Api::GlobalStats.new
        result = stats.to_h

        assert result.has_key?("total_jobs")
        assert result.has_key?("active_executors")
        assert result.has_key?("processing_rate")
        assert result["total_jobs"].is_a?(Int64)
      end
    end
  end
end

describe Mosquito::Api::QueueStats do
  describe "#name" do
    it "provides queue-specific statistics" do
      clean_slate do
        queue = Mosquito::Api::Queue.new("test_queue")
        stats = Mosquito::Api::QueueStats.new(queue)

        assert_equal "test_queue", stats.name
        assert stats.total_count.is_a?(Int64)
        assert stats.processing_rate.is_a?(Float64)
      end
    end
  end

  describe "#to_h" do
    it "serializes to hash correctly" do
      clean_slate do
        queue = Mosquito::Api::Queue.new("test_queue")
        stats = Mosquito::Api::QueueStats.new(queue)
        result = stats.to_h

        assert result.has_key?("name")
        assert result.has_key?("waiting_count")
        assert result.has_key?("pending_count")
        assert result.has_key?("dead_count")
        assert_equal "test_queue", result["name"]
      end
    end
  end
end

describe Mosquito::Api::ClusterStats do
  describe "#health_status" do
    it "calculates cluster health status" do
      clean_slate do
        stats = Mosquito::Api::ClusterStats.new
        health = stats.health_status

        assert ["healthy", "warning", "unhealthy"].includes?(health)
      end
    end
  end

  describe "#dead_jobs_ratio" do
    it "calculates dead jobs ratio" do
      clean_slate do
        stats = Mosquito::Api::ClusterStats.new
        ratio = stats.dead_jobs_ratio

        assert ratio >= 0.0
        assert ratio <= 1.0
      end
    end
  end

  describe "#executor_utilization" do
    it "calculates executor utilization" do
      clean_slate do
        stats = Mosquito::Api::ClusterStats.new
        utilization = stats.executor_utilization

        assert utilization >= 0.0
        assert utilization <= 100.0
      end
    end
  end
end
