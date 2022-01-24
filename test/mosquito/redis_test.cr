require "../test_helper"

describe Mosquito::Redis do
  let(:redis) {
    Mosquito::Redis.instance
  }

  it "is a singleton" do
    assert_equal Mosquito::Redis.instance.object_id, redis.object_id
  end
end
