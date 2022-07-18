require "../test_helper"

describe Mosquito::RedisBackend do
  getter(:key) { "key-#{rand 1000}" }
  getter(:field) { "field-#{rand 1000}" }

  describe "self.get and set" do
    it "sets and retrieves a value from a hash" do
      RedisBackend.set(key, field, "truth")
      assert_equal "truth", RedisBackend.get(key, field)
    end
  end

  describe "self.increment" do
    it "adds one" do
      RedisBackend.set(key, field, "1")
      assert_equal 2, RedisBackend.increment(key, field)
    end

    it "can add arbitrary values" do
      RedisBackend.set(key, field, "1")
      assert_equal 4, RedisBackend.increment(key, field, by: 3)
    end
  end

  describe "dump_q" do
    it "can dump the waiting q" do
      skip
    end

    it "can dump the scheduled q" do
      skip
    end

    it "can dump the pending q" do
      skip
    end

    it "can dump the dead q" do
      skip
    end
  end

  describe "list_runners" do
    it "can list runners" do
      skip
    end
  end
end
