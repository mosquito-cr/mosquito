require "uuid"
require "../../test_helper"

class PrimitiveSerializerTester
  extend Mosquito::Serializers::Primitives
end

describe Mosquito::Serializers::Primitives do
  it "serializes uuids" do
    uuid = UUID.random
    assert_equal uuid, UUID.new(PrimitiveSerializerTester.serialize_uuid(uuid))
  end

  it "deserializes uuids" do
    uuid = UUID.random.to_s
    assert_equal uuid, PrimitiveSerializerTester.deserialize_uuid(uuid).to_s
  end
end
