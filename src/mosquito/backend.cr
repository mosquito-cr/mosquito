require "json"

module Mosquito
  abstract class Backend
    struct BroadcastMessage
      include JSON::Serializable

      property channel : String
      property message : String

      def initialize(@channel, @message)
      end
    end

    QUEUES = %w(waiting scheduled pending dead)

    KEY_PREFIX = {"mosquito"}

    def self.named(name)
      new(name)
    end

    def self.build_key(*parts)
      KeyBuilder.build Mosquito.configuration.global_prefix, KEY_PREFIX, *parts
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
      abstract def delete(key : String, in ttl : Time::Span = 0.seconds)
      abstract def increment(key : String, by value : Int32) : Int64
      abstract def increment(key : String, field : String) : Int64
      abstract def increment(key : String, field : String, by value : Int32) : Int64

      abstract def flush : Nil

      abstract def unlock(key : String, value : String) : Nil
      abstract def lock?(key : String, value : String, ttl : Time::Span) : Bool
      abstract def publish(key : String, value : String) : Nil
      abstract def subscribe(key : String) : Channel(BroadcastMessage)

      abstract def average_push(key : String, value : Int32, window_size : Int32 = 100) : Nil
      abstract def average(key : String) : Int32
    end

    macro inherited
      extend ClassMethods
    end

    def self.search_queues
      QUEUES.first(2)
    end

    {% for q_name in QUEUES %}
      def {{q_name.id}}_q
        build_key {{q_name}}, name
      end

      abstract def dump_{{q_name.id}}_q : Array(String)
      abstract def {{ q_name.id }}_size : Int64
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

    abstract def enqueue(job_run : JobRun) : JobRun
    abstract def dequeue : JobRun?
    abstract def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
    abstract def deschedule : Array(JobRun)
    abstract def finish(job_run : JobRun)    # should this be called succeed?
    abstract def terminate(job_run : JobRun) # should this be called fail?
    abstract def flush : Nil
    abstract def size(include_dead : Bool = true) : Int64

    abstract def scheduled_job_run_time(job_run : JobRun) : String?
    abstract def increment(key : String, by value : Int32 = 1) : Int64
  end
end
