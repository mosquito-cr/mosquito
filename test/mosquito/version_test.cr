require "../test_helper"
require "yaml"

describe "mosquito version numbers" do
  it "is defined" do
    assert Mosquito::VERSION
  end

  it "matches the shard.yml file" do
    File.open("shard.yml") do |file|
      assert_equal Mosquito::VERSION, YAML.parse(file)["version"].as_s
    end
  end
end
