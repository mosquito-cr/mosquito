require "../test_helper"

describe Mosquito::Metadata do
  getter(store_name : String) { "test_store#{rand 1000}" }
  getter(store : Metadata) { Metadata.new store_name }
  getter(field : String) { "foo#{rand 1000}" }

  it "increments" do
    clean_slate do
      store.increment field
      value = store[field]?
      assert_equal "1", value

      store.increment field
      value = store[field]?
      assert_equal "2", value
    end
  end

  it "decrements" do
    clean_slate do
      store.decrement field
      value = store[field]?
      assert_equal "-1", value

      store.decrement field
      value = store[field]?
      assert_equal "-2", value
    end
  end

  it "dumps to a hash" do
    clean_slate do
      expected = { "one" => "1", "two" => "2", "three" => "3" }

      expected.each { |key, value| store[key] = value }

      assert_equal expected, store.to_h
    end
  end

  it "can be readonly" do
    clean_slate do
      store[field] = "truth"
      readonly_store = Metadata.new store_name, readonly: true
      assert_equal "truth", readonly_store[field]?

      assert_raises RuntimeError do
        readonly_store[field] = "lies"
      end
    end
  end

  it "can set and read a value" do
    clean_slate do
      store[field] = "truth"
      assert_equal "truth", store[field]?
    end
  end
end
