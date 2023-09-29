require "./mosquito/runners/run_at_most"

require "./mosquito/**"

module Mosquito
  def self.backend
    configuration.backend
  end
end
