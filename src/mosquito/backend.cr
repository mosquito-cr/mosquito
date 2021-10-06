module Mosquito
  module Backend
    def self.instance
      @@instance ||= new
    end

    # from runner.cr
    abstract def store_job_config(job : Mosquito::Job.class) : Nil
  end
end
