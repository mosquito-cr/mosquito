require "./backend"
require "./api/*"

module Mosquito::Api
  def self.executor(id : String) : Executor
    Executor.new id
  end

  def self.job_run(id : String) : JobRun
    JobRun.new id
  end
end
