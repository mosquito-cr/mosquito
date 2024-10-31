require "./mosquito/runners/run_at_most"

require "./mosquito/**"

module Mosquito
  Log = ::Log.for self

  def self.backend
    configuration.backend
  end
end
