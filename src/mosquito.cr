require "./mosquito/runners/base"

require "./mosquito/**"

module Mosquito
  def self.backend
    configuration.backend
  end
end
