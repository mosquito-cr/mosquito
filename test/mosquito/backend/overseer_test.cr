require "../../test_helper"

describe Mosquito::Backend do
  it "can keep a list of overseers" do
    overseer_ids = ["overseer1", "overseer2", "overseer3"]
    overseer_ids.each do |overseer_id|
      Mosquito.backend.register_overseer overseer_id
    end

    assert_equal overseer_ids, Mosquito.backend.list_overseers
  end
end
