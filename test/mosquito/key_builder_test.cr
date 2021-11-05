require "../test_helper"

describe Mosquito::KeyBuilder do
  it "builds keys from tuples" do
    assert_equal "fizz:buzz", KeyBuilder.build({:fizz, :buzz})
  end

  it "builds keys from strings" do
    assert_equal "fizz:buzz", KeyBuilder.build("fizz", "buzz")
  end

  it "builds keys from an array" do
    assert_equal "fizz:buzz", KeyBuilder.build(["fizz", "buzz"])
  end

  it "builds keys from integers" do
    assert_equal "fizz:6", KeyBuilder.build("fizz", 6)
  end

  it "builds keys from floats" do
    assert_equal "2.4:buzz", KeyBuilder.build(2.4, "buzz")
  end
end
