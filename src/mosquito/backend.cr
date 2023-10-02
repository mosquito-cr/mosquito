module Mosquito
  abstract class Backend
    QUEUES = %w(waiting scheduled pending dead)

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

    def initialize(name : String | Symbol)
      @name = name.to_s
    end

    module ClassMethods
      abstract def store(key : String, value : Hash(String, String)) : Nil
      abstract def retrieve(key : String) : Hash(String, String)
      abstract def list_queues : Array(String)
      abstract def list_runners : Array(String)

      abstract def delete(key : String, in ttl : Int64 = 0) : Nil
      abstract def delete(key : String, in ttl : Time::Span) : Nil
      abstract def expires_in(key : String) : Int64

      abstract def get(key : String, field : String) : String?
      abstract def set(key : String, field : String, value : String) : String
      abstract def increment(key : String, field : String) : Int64
      abstract def increment(key : String, field : String, by value : Int32) : Int64

      abstract def flush : Nil

      abstract def unlock(key : String, value : String) : Nil
      abstract def lock?(key : String, value : String, ttl : Time::Span) : Bool
    end

    macro inherited
      extend ClassMethods
    end

    def self.search_queues
      QUEUES.first(2)
    end

    {% for q in QUEUES %}
      def {{q.id}}_q
        build_key {{q}}, name
      end
    {% end %}

    def store(key : String, value : Hash(String, String)) : Nil
      self.class.store key, value
    end

    def retrieve(key : String) : Hash(String, String)
      self.class.retrieve key
    end

    def delete(key : String, in ttl = 0) : Nil
      self.class.delete key
    end

    def expires_in(key : String) : Int64
      self.class.expires_in key
    end

    # from queue.cr
    abstract def enqueue(job_run : JobRun) : JobRun
    abstract def dequeue : JobRun?
    abstract def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
    abstract def deschedule : Array(JobRun)
    abstract def finish(job_run : JobRun) # should this be called succeed?
    abstract def terminate(job_run : JobRun) # should this be called fail?
    abstract def flush : Nil
    abstract def size(include_dead : Bool = true) : Int64

    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      abstract def dump_{{name.id}}_q : Array(String)
    {% end %}

    abstract def scheduled_job_run_time(job_run : JobRun) : String?

  end
end
