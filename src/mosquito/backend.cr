module Mosquito
  abstract class Backend
    KEY_PREFIX = {"mosquito"}

    def self.named(name)
      new(name)
    end

    def self.build_key(*parts)
      KeyBuilder.build KEY_PREFIX, *parts
    end

    def build_key(*parts)
      self.class.build_key *parts
    end

    private getter name : String

    def initialize(@name : String)
    end

    module ClassMethods
      # from queue.cr
      abstract def store(key : String, value : Hash(String, String)) : Nil
      abstract def retrieve(key : String) : Hash(String, String)
      abstract def list_queues : Array(String)

      # from task.cr
      abstract def delete(key : String, in ttl = 0) : Nil
      abstract def expires_in(key : String) : Int64

      abstract def flush : Nil
    end

    macro inherited
      extend ClassMethods
    end

    def store(key : String, value : Hash(String, String)) : Nil
      self.class.store key, value
    end

    def retrieve(key : String) : Hash(String, String)
      self.class.retrieve key
    end

    def expires_in(key : String) : Int64
      self.class.expires_in key
    end

    # from queue.cr
    abstract def enqueue(task : Task) : Task
    abstract def dequeue : Task?
    abstract def schedule(task : Task, at scheduled_time : Time) : Task
    abstract def deschedule : Array(Task)
    abstract def finish(task : Task) # should this be called succeed?
    abstract def terminate(task : Task) # should this be called fail?
    abstract def flush : Nil
    abstract def size : Int64
  end
end
