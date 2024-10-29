require "../../test_helper"

describe Mosquito::Backend do
  describe "expiring lists" do
    it "can add an item to a list" do
      now = Time.utc
      key = "exp-list-test"
      items = ["item1", "item2", "item3"]

      Timecop.freeze now do
        backend.expiring_list_push key, items[0]
      end

      Timecop.freeze now + 1.second do
        backend.expiring_list_push key, items[1]
      end

      Timecop.freeze now + 2.seconds do
        backend.expiring_list_push key, items[2]
      end

      found_items = backend.expiring_list_fetch(key, now + 1.second)
      assert_equal [items[2]], found_items
    end
  end
end
