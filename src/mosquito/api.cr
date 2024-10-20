require "./backend"
require "./api/*"

module Mosquito::Api
  def self.executor(id : String) : Executor
    Executor.new id
  end
end
