module Mosquito
  module Backend
    def self.instance
      @@instance ||= new
    end

    # from runner.cr
    abstract def store_job_config(job : Mosquito::Job.class) : Nil

    # from queue.cr
    abstract def enqueue(queue_name : String, task : Task)
    abstract def dequeue(queue_name : String) : Task?
    abstract def schedule(queue_name : String, task : Task, at scheduled_time : Time)
    abstract def deschedule(queue_name : String) : Array(Task)
    abstract def finish(queue_name : String, task : Task) # should this be called succeed?
    abstract def terminate(queue_name : String, task : Task) # should this be called fail?
    abstract def flush(queue_name : String)
  end
end
