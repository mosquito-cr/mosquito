module Mosquito
  module Backend
    def self.instance
      @@instance ||= new
    end

    # from runner.cr
    abstract def store_job_config(job : Mosquito::Job.class) : Nil

    # from queue.cr
    abstract def enqueue(queue_name : String, task : Task)
  end
end
