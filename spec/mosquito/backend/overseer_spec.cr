require "../../spec_helper"

describe Mosquito::Backend do
  it "can keep a list of overseers" do
    clean_slate do
      overseer_ids = ["overseer1", "overseer2", "overseer3"]
      overseer_ids.each do |overseer_id|
        Mosquito.backend.register_overseer overseer_id
      end

      assert_equal overseer_ids, Mosquito.backend.list_overseers
    end
  end

  it "can deregister an overseer" do
    clean_slate do
      overseer_ids = ["overseer1", "overseer2", "overseer3"]
      overseer_ids.each do |overseer_id|
        Mosquito.backend.register_overseer overseer_id
      end

      Mosquito.backend.deregister_overseer "overseer2"

      assert_equal ["overseer1", "overseer3"], Mosquito.backend.list_overseers
    end
  end
end
