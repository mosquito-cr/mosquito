require "habitat"

require "./external_classes"
require "./mosquito/*"

module Mosquito
  Habitat.create do
    setting redis_url : String? = ENV["REDIS_URL"]?
  end
end
