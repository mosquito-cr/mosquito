require "../test_helper"

describe Mosquito::Redis do
  let(:data) {
    {
      "question" => "unknown",
      "answer"   => "forty-two",
    }
  }

  let(:redis) {
    Mosquito::Redis.instance
  }

  it "is a singleton" do
    assert_equal Mosquito::Redis.instance.object_id, redis.object_id
  end

  it "can store and retrieve a hash" do
    key = "hash_storage"

    redis.store_hash(key, data)
    result = redis.retrieve_hash(key)

    assert_equal data, result
  end

  it "can build a key with two strings" do
    assert_equal "one:two", Mosquito::Redis.key("one", "two")
  end

  it "can build a key with an array" do
    assert_equal "one:two", Mosquito::Redis.key(["one", "two"])
  end

  it "can build a key with a tuple" do
    assert_equal "one:two", Mosquito::Redis.key(*{"one", "two"})
  end
end
