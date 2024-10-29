require "../../spec_helper"

describe "Backend hash storage" do
  getter sample_data : Hash(String,String) { { "test" => "#{rand(1000)}" } }
  getter key : String { "key-#{rand 1000}" }
  getter field : String { "field-#{rand 1000}" }

  it "can store and retrieve" do
    backend.store key, sample_data
    retrieved_data = backend.retrieve key
    assert_equal sample_data, retrieved_data
  end

  describe "self.get and set" do
    it "sets and retrieves a value from a hash" do
      backend.set(key, field, "truth")
      assert_equal "truth", backend.get(key, field)
    end
  end

  describe "self.increment" do
    it "adds one" do
      backend.set(key, field, "1")
      assert_equal 2, backend.increment(key, field)
    end

    it "can add arbitrary values" do
      backend.set(key, field, "1")
      assert_equal 4, backend.increment(key, field, by: 3)
    end
  end
end
