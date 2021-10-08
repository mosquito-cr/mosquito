module Mosquito
  abstract class Backend
    KEY_PREFIX = {"mosquito"}

    def self.named(name)
      new(name)
    end

    def self.key(*parts)
      KeyBuilder.build KEY_PREFIX, *parts
    end

    def key(*parts)
      self.class.key *parts
    end

    private getter name : String

    def initialize(@name : String)
    end

    module ClassMethods
      # from runner.cr
      abstract def store_job_config(job : Mosquito::Job.class) : Nil

      # from queue.cr
      abstract def store(key : String, value : Hash(String, String)) : Nil
      abstract def retrieve(key : String) : Hash(String, String)
      abstract def list_queues : Array(String)

      # from task.cr
      abstract def delete(key : String, in ttl = 0) : Nil
    end

    macro inherited
      extend ClassMethods
    end

    # from queue.cr
    abstract def enqueue(task : Task)
    abstract def dequeue : Task?
    abstract def schedule(task : Task, at scheduled_time : Time)
    abstract def deschedule : Array(Task)
    abstract def finish(task : Task) # should this be called succeed?
    abstract def terminate(task : Task) # should this be called fail?
    abstract def flush : Nil
    abstract def size : Int32
  end
end
