require "../../spec_helper"

describe "Mosquito::Api::ExecutorConfig" do
  describe "global executor count" do
    it "returns nil when no override is stored" do
      clean_slate do
        result = Mosquito::Api::ExecutorConfig.stored_executor_count
        assert_nil result
      end
    end

    it "round-trips a global executor count" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)
        result = Mosquito::Api::ExecutorConfig.stored_executor_count
        assert_equal 8, result
      end
    end

    it "clears the global executor count" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)
        Mosquito::Api::ExecutorConfig.clear_executor_count

        result = Mosquito::Api::ExecutorConfig.stored_executor_count
        assert_nil result
      end
    end
  end

  describe "per-overseer executor count" do
    it "returns nil when no per-overseer override is stored" do
      clean_slate do
        result = Mosquito::Api::ExecutorConfig.stored_executor_count("gpu-worker-1")
        assert_nil result
      end
    end

    it "round-trips a per-overseer executor count" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(2, "gpu-worker-1")

        result = Mosquito::Api::ExecutorConfig.stored_executor_count("gpu-worker-1")
        assert_equal 2, result

        # Global is unaffected.
        global = Mosquito::Api::ExecutorConfig.stored_executor_count
        assert_nil global
      end
    end

    it "clears per-overseer without affecting global" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)
        Mosquito::Api::ExecutorConfig.store_executor_count(2, "gpu-worker-1")

        Mosquito::Api::ExecutorConfig.clear_executor_count("gpu-worker-1")

        per_overseer = Mosquito::Api::ExecutorConfig.stored_executor_count("gpu-worker-1")
        assert_nil per_overseer

        global = Mosquito::Api::ExecutorConfig.stored_executor_count
        assert_equal 8, global
      end
    end
  end

  describe ".resolve" do
    it "returns nil when nothing is stored" do
      clean_slate do
        result = Mosquito::Api::ExecutorConfig.resolve
        assert_nil result
      end
    end

    it "returns the global count when no overseer_id is given" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)
        result = Mosquito::Api::ExecutorConfig.resolve
        assert_equal 8, result
      end
    end

    it "prefers per-overseer over global" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)
        Mosquito::Api::ExecutorConfig.store_executor_count(2, "gpu-worker-1")

        result = Mosquito::Api::ExecutorConfig.resolve("gpu-worker-1")
        assert_equal 2, result
      end
    end

    it "falls back to global when per-overseer is not set" do
      clean_slate do
        Mosquito::Api::ExecutorConfig.store_executor_count(8)

        result = Mosquito::Api::ExecutorConfig.resolve("gpu-worker-1")
        assert_equal 8, result
      end
    end
  end

  describe "instance methods" do
    it "delegates to class-level helpers" do
      clean_slate do
        config = Mosquito::Api::ExecutorConfig.instance

        config.update(10)
        assert_equal 10, config.executor_count

        config.update(3, overseer_id: "worker-1")
        assert_equal 3, config.executor_count(overseer_id: "worker-1")

        config.clear(overseer_id: "worker-1")
        assert_nil config.executor_count(overseer_id: "worker-1")

        config.clear
        assert_nil config.executor_count
      end
    end
  end
end

describe "Mosquito::Api executor count convenience methods" do
  it "reads and writes global executor count" do
    clean_slate do
      Mosquito::Api.set_executor_count(12)
      assert_equal 12, Mosquito::Api.executor_count
    end
  end

  it "reads and writes per-overseer executor count" do
    clean_slate do
      Mosquito::Api.set_executor_count(4, overseer_id: "gpu-worker-1")
      assert_equal 4, Mosquito::Api.executor_count(overseer_id: "gpu-worker-1")

      # Global unaffected.
      assert_nil Mosquito::Api.executor_count
    end
  end
end
