module Mosquito
  abstract class Backend
    struct BroadcastMessage
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
      abstract def list_overseers : Array(String)
      abstract def register_overseer(id : String) : Nil

      abstract def delete(key : String, in ttl : Int64 = 0) : Nil
      abstract def delete(key : String, in ttl : Time::Span) : Nil
      abstract def expires_in(key : String) : Int64

      abstract def get(key : String, field : String) : String?
      abstract def set(key : String, field : String, value : String) : String
      abstract def set(key : String, values : Hash(String, String?) | Hash(String, Nil) | Hash(String, String)) : Nil
      abstract def delete_field(key : String, field : String) : Nil
      abstract def increment(key : String, field : String) : Int64
      abstract def increment(key : String, field : String, by value : Int32) : Int64

      abstract def flush : Nil

      abstract def unlock(key : String, value : String) : Nil
      abstract def lock?(key : String, value : String, ttl : Time::Span) : Bool
      abstract def publish(key : String, value : String) : Nil
      abstract def subscribe(key : String) : Channel(BroadcastMessage)
      
      # Health check - backends can override to provide actual health status
      def healthy? : Bool
        true
      end
      
      # Connection info - backends can provide connection pool stats, etc.
      def connection_info : Hash(String, String | Int32 | Float64)
        {} of String => String | Int32 | Float64
      end
      
      # Maintenance operations - backends can implement cleanup logic
      def cleanup_expired : Int32
        0
      end
      
      # Global queue statistics across all queues
      def queue_stats : Hash(String, Hash(String, Int64))
        stats = {} of String => Hash(String, Int64)
        list_queues.each do |queue_name|
          backend = named(queue_name)
          stats[queue_name] = {
            "waiting" => backend.waiting_size,
            "scheduled" => backend.scheduled_size,
            "pending" => backend.pending_size,
            "dead" => backend.dead_size,
            "total" => backend.size(include_dead: true)
          }
        end
        stats
      end
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
    abstract def finish(job_run : JobRun)    # should this be called succeed?
    abstract def terminate(job_run : JobRun) # should this be called fail?
    abstract def flush : Nil
    abstract def size(include_dead : Bool = true) : Int64

    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      abstract def dump_{{name.id}}_q : Array(String)
    {% end %}

    abstract def scheduled_job_run_time(job_run : JobRun) : String?
    
    # Queue-specific size methods for efficiency
    abstract def waiting_size : Int64
    abstract def scheduled_size : Int64
    abstract def pending_size : Int64
    abstract def dead_size : Int64
    
    # Batch operations with default implementations
    # Backends can override for better performance
    def enqueue_batch(job_runs : Array(JobRun)) : Array(JobRun)
      job_runs.each { |job_run| enqueue(job_run) }
      job_runs
    end
    
    def dequeue_batch(limit : Int32 = 10) : Array(JobRun)
      jobs = [] of JobRun
      limit.times do
        if job = dequeue
          jobs << job
        else
          break
        end
      end
      jobs
    end
    
    # Transaction support for backends that support it
    def transaction(&block : -> T) : T forall T
      yield # Default implementation, backends can wrap with actual transactions
    end
    
    # Find a specific job across all queues
    def find_job(job_id : String) : JobRun?
      {% for queue_type in ["waiting", "scheduled", "pending", "dead"] %}
        dump_{{queue_type.id}}_q.each do |job_data|
          if job_run = JobRun.retrieve(job_data)
            return job_run if job_run.id == job_id
          end
        end
      {% end %}
      nil
    end
    
    # Move a job from dead queue back to waiting
    def resurrect_job(job_id : String) : Bool
      dead_jobs = dump_dead_q
      dead_jobs.each do |job_data|
        if job_run = JobRun.retrieve(job_data)
          if job_run.id == job_id
            # This would need backend-specific implementation
            # For now, return false as it needs to be implemented per backend
            return false
          end
        end
      end
      false
    end
  end
end
