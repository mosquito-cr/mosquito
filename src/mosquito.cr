require "habitat"

require "./mosquito/*"

module Mosquito
  def self.backend
    configuration.backend
  end
end
