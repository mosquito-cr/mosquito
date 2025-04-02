require "../spec_helper"

# These tests are explicitly for code which is inherited from the abstract Backend
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

  it "can be initialized with a string name" do
    Mosquito.backend.named "string_backend"
  end

  it "can be initialized with a symbol name" do
    Mosquito.backend.named :symbol_backend
  end

  it "can update a key with a hash" do
    Mosquito.backend.set "key", {"field" => "value", "field2" => "value2"}
    assert_equal "value", Mosquito.backend.get("key", "field")
    assert_equal "value2", Mosquito.backend.get("key", "field2")
  end
end
