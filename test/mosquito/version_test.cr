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

describe "crystal version numbers" do
  it "matches" do
    version_file_contents = File.read(".crystal-version").strip
    File.open("shard.yml") do |file|
      assert_equal version_file_contents, YAML.parse(file)["crystal"].as_s
    end
  end
end
