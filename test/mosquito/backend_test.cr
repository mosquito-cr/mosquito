require "../test_helper"

describe Mosquito::Backend do
  it "can build a key with two strings" do
    assert_equal "mosquito:one:two", Mosquito.backend.build_key("one", "two")
  end

  it "can build a key with an array" do
    assert_equal "mosquito:one:two", Mosquito.backend.build_key(["one", "two"])
  end

  it "can build a key with a tuple" do
    assert_equal "mosquito:one:two", Mosquito.backend.build_key(*{"one", "two"})
  end
end
