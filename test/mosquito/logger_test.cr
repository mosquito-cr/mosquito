require "../test_helper"

describe Mosquito::Logger do
  it "is a Logger" do
    assert_instance_of ::Logger, Mosquito::Logger.new(nil)
  end
end
