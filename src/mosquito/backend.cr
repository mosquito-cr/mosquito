module Mosquito
  abstract class Backend
    struct BroadcastMessage
      property channel : String
      property message : String

      def initialize(@channel, @message)
      end
    end

    # The lifecycle states a job run passes through in any backend.
    QUEUES = %w(waiting scheduled pending dead)

    KEY_PREFIX = {"mosquito"}

    def build_key(*parts)
      KeyBuilder.build Mosquito.configuration.global_prefix, KEY_PREFIX, *parts
    end

    # Factory method to create a named queue for this backend.
    def queue(name : String | Symbol) : Queue
      _build_queue(name.to_s)
    end

    protected abstract def _build_queue(name : String) : Queue

    # Storage
    abstract def store(key : String, value : Hash(String, String?) | Hash(String, String)) : Nil
    abstract def retrieve(key : String) : Hash(String, String)

    abstract def delete(key : String, in ttl : Int64 = 0) : Nil
    abstract def delete(key : String, in ttl : Time::Span) : Nil
    abstract def expires_in(key : String) : Int64

    abstract def get(key : String, field : String) : String?
    abstract def set(key : String, field : String, value : String) : String
    abstract def set(key : String, values : Hash(String, String?) | Hash(String, Nil) | Hash(String, String)) : Nil
    abstract def delete_field(key : String, field : String) : Nil
    abstract def increment(key : String, field : String) : Int64
    abstract def increment(key : String, field : String, by value : Int32) : Int64

    # Global
    abstract def list_queues : Array(String)
    abstract def list_overseers : Array(String)
    abstract def list_active_overseers(since : Time) : Array(String)
    abstract def register_overseer(id : String) : Nil
    abstract def deregister_overseer(id : String) : Nil
    abstract def flush : Nil

    # Coordination
    abstract def unlock(key : String, value : String) : Nil
    abstract def lock?(key : String, value : String, ttl : Time::Span) : Bool
    abstract def publish(key : String, value : String) : Nil
    abstract def subscribe(key : String) : Channel(BroadcastMessage)

    # Metrics
    abstract def average_push(key : String, value : Int32, window_size : Int32 = 100) : Nil
    abstract def average(key : String) : Int32

    abstract class Queue
      getter backend : Backend
      private getter name : String

      def initialize(@backend, @name : String)
      end

      # Queue operations
      abstract def enqueue(job_run : JobRun) : JobRun
      abstract def dequeue : JobRun?
      abstract def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
      abstract def deschedule : Array(JobRun)
      abstract def finish(job_run : JobRun)
      abstract def terminate(job_run : JobRun)
      abstract def undequeue : JobRun?
      abstract def flush : Nil
      abstract def size(include_dead : Bool = true) : Int64

      {% for name in ["waiting", "scheduled", "pending", "dead"] %}
        abstract def list_{{name.id}} : Array(String)
        abstract def {{name.id}}_size : Int64
      {% end %}

      abstract def scheduled_job_run_time(job_run : JobRun) : Time?

      # Pause this queue so that `#dequeue` returns nil until it is resumed
      # or the optional duration expires.
      abstract def pause(duration : Time::Span? = nil) : Nil

      # Resume a paused queue, allowing dequeue to proceed.
      abstract def resume : Nil
      abstract def paused? : Bool

    end
  end
end
