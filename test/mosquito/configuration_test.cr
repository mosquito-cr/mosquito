require "../test_helper"

describe "Mosquito Config" do
  it "allows setting / retrieving the redis url" do
    Mosquito.temp_config(redis_url: "yolo") do
      assert_equal "yolo", Mosquito.settings.redis_url
    end
  end

  it "enforces missing settings are set" do
  end
end
