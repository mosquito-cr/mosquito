module Mosquito
  # An in-memory noop backend desigend to be used in application testing.
  #
  # The test mode backend simply makes a copy of job_runs at enqueue time and holds them in a class getter array.
  #
  # Job run id, config (aka parameters), and runtime class are kept in memory, and a truncate utility function is provided.
  #
  # Activate test mode configure the test backend like this:
  #
  # ```
  # Mosquito.configure do |settings|
  #   settings.backend = Mosquito::TestBackend.new
  # end
  # ```
  #
  # Then in your tests:
  #
  # ```
  # describe "testing" do
  #   it "enqueues the job" do
  #     # build and enqueue a job
  #     job_run = EchoJob.new(text: "hello world").enqueue
  #
  #     # assert that the job was enqueued
  #     lastest_enqueued_job = Mosquito::TestBackend.enqueued_jobs.last
  #
  #     # check the job config
  #     assert_equal "hello world", latest_enqueued_job.config["text"]
  #
  #     # check the job_id matches
  #     assert_equal job_run.id, latest_enqueued_job.id
  #
  #     # optionally, truncate the history
  #     Mosquito::TestBackend.flush_enqueued_jobs!
  #   end
  # end
  # ```
  class TestBackend < Mosquito::Backend
    getter connection_string : String?

    def connection_string=(value : String)
      @connection_string = value
    end

    def valid_configuration? : Bool
      true
    end

    def store(key : String, value : Hash(String, String?) | Hash(String, String)) : Nil
    end

    def retrieve(key : String) : Hash(String, String)
      {} of String => String
    end

    def list_queues : Array(String)
      [] of String
    end

    def list_overseers : Array(String)
      [] of String
    end

    def list_active_overseers(since : Time) : Array(String)
      [] of String
    end

    def register_overseer(id : String) : Nil
    end

    def deregister_overseer(id : String) : Nil
    end

    def delete(key : String, in ttl : Int64 = 0) : Nil
    end

    def delete(key : String, in ttl : Time::Span) : Nil
    end

    def expires_in(key : String) : Int64
      0_i64
    end

    def get(key : String, field : String) : String?
    end

    def set(key : String, field : String, value : String) : String
      ""
    end

    def set(key : String, values : Hash(String, String?) | Hash(String, Nil) | Hash(String, String)) : Nil
    end

    def delete_field(key : String, field : String) : Nil
    end

    def increment(key : String, field : String) : Int64
      0_i64
    end

    def increment(key : String, field : String, by value : Int32) : Int64
      0_i64
    end

    def flush : Nil; end

    def lock?(key : String, value : String, ttl : Time::Span) : Bool
      false
    end

    def unlock(key : String, value : String) : Nil
    end

    def publish(key : String, value : String) : Nil
    end

    def subscribe(key : String) : Channel(BroadcastMessage)
      Channel(BroadcastMessage).new
    end

    def average_push(key : String, value : Int32, window_size : Int32 = 100) : Nil
    end

    def average(key : String) : Int32
      0_i32
    end

    protected def _build_queue(name : String) : Queue
      Queue.new(self, name)
    end

    struct EnqueuedJob
      getter id : String
      getter klass : Mosquito::Job.class
      getter config : Hash(String, String)

      def self.from(job_run : JobRun)
        job_class = Mosquito::Base.job_for_type(job_run.type)
        new(
          job_run.id,
          job_class,
          job_run.config
        )
      end

      def initialize(@id, @klass, @config)
      end
    end

    class_property enqueued_jobs = [] of EnqueuedJob

    def self.flush_enqueued_jobs!
      @@enqueued_jobs = [] of EnqueuedJob
    end

    class Queue < Backend::Queue
      def enqueue(job_run : JobRun) : JobRun
        TestBackend.enqueued_jobs << EnqueuedJob.from(job_run)
        job_run
      end

      def dequeue : JobRun?
        raise "Mosquito: attempted to dequeue a job from the testing backend."
      end

      def schedule(job_run : JobRun, at scheduled_time : Time) : JobRun
        job_run
      end

      def deschedule : Array(JobRun)
        raise "Mosquito: attempted to deschedule a job from the testing backend."
      end

      def undequeue : JobRun?
        raise "Mosquito: attempted to undequeue a job from the testing backend."
      end

      def finish(job_run : JobRun)
      end

      def terminate(job_run : JobRun)
      end

      def flush : Nil
      end

      def size(include_dead : Bool = true) : Int64
        0_i64
      end

      {% for name in ["waiting", "scheduled", "pending", "dead"] %}
        def list_{{name.id}} : Array(String)
          [] of String
        end

        def {{name.id}}_size : Int64
          0_i64
        end
      {% end %}

      def scheduled_job_run_time(job_run : JobRun) : Time?
      end

      @@paused_queues = Set(String).new

      def self.flush_paused_queues!
        @@paused_queues.clear
      end

      def pause(duration : Time::Span? = nil) : Nil
        @@paused_queues.add name
      end

      def resume : Nil
        @@paused_queues.delete name
      end

      def paused? : Bool
        @@paused_queues.includes? name
      end
    end
  end
end
