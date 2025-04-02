require "../spec_helper"

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

  it "increments with a configurable amount" do
    clean_slate do
      store.increment field
      value = store[field]?.not_nil!
      assert_equal "1", value

      delta = 2
      store.increment field, by: delta
      new_value = store[field]?.not_nil!
      assert_equal delta, (new_value.to_i - value.to_i)
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

  describe "with a hash" do
    it "can set and read a hash" do
      clean_slate do
        store.set({"one" => "1", "two" => "2", "three" => "3"})
        assert_equal "1", store["one"]?
        assert_equal "2", store["two"]?
        assert_equal "3", store["three"]?
      end
    end

    it "can set a hash and delete a value from the hash" do
      clean_slate do
        store.set({"one" => "1", "two" => "2", "three" => "3"})
        store.set({"two" => nil, "six" => "6"})
        assert_equal "1", store["one"]?
        assert_equal nil, store["two"]?
        assert_equal "3", store["three"]?
        assert_equal "6", store["six"]?
      end
    end
  end

  it "can be deleted" do
    clean_slate do
      store[field] = "truth"
      assert_equal "truth", store[field]?
      store.delete
      assert_equal nil, Metadata.new(store_name)[field]?
    end
  end

  it "can be deleted with a ttl" do
    clean_slate do
      store[field] = "truth"
      assert_equal "truth", store[field]?
      store.delete(in: 1.minute)
      assert_in_epsilon(60, Mosquito.backend.expires_in(store_name))
      store.delete
    end
  end
end
