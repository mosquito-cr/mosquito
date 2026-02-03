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
  #   settings.backend = Mosquito::TestBackend
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
    def self.store(key : String, value : Hash(String, String)) : Nil
    end

    def self.retrieve(key : String) : Hash(String, String)
      {} of String => String
    end

    def self.list_queues : Array(String)
      [] of String
    end

    def self.list_overseers : Array(String)
      [] of String
    end

    def self.expiring_list_push(key : String, value : String) : Nil
    end

    def self.expiring_list_fetch(key : String, expire_items_older_than : Time) : Array(String)
      [] of String
    end

    def self.register_overseer(id : String) : Nil
    end

    def self.delete(key : String, in ttl : Int64 = 0) : Nil
    end

    def self.delete(key : String, in ttl : Time::Span) : Nil
    end

    def self.expires_in(key : String) : Int64
      0_i64
    end

    def self.get(key : String, field : String) : String?
    end

    def self.set(key : String, field : String, value : String) : String
      ""
    end

    def self.set(key : String, values : Hash(String, String?) | Hash(String, Nil) | Hash(String, String)) : Nil
    end

    def self.delete_field(key : String, field : String) : Nil
    end

    def self.increment(key : String, field : String) : Int64
      0_i64
    end

    def self.increment(key : String, field : String, by value : Int32) : Int64
      0_i64
    end

    def self.flush : Nil; end

    def self.lock?(key : String, value : String, ttl : Time::Span) : Bool
      false
    end

    def self.unlock(key : String, value : String) : Nil
    end

    def self.publish(key : String, value : String) : Nil
    end

    def self.subscribe(key : String) : Channel(BroadcastMessage)
      Channel(BroadcastMessage).new
    end

    def self.average_push(key : String, value : Int32, window_size : Int32 = 100) : Nil
    end

    def self.average(key : String) : Int32
      0_i32
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

    def enqueue(job_run : JobRun) : JobRun
      @@enqueued_jobs << EnqueuedJob.from(job_run)
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

    def finish(job_run : JobRun) # should this be called succeed?
    end

    def terminate(job_run : JobRun) # should this be called fail?
    end

    def flush : Nil
    end

    def size(include_dead : Bool = true) : Int64
      0_i64
    end

    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      def dump_{{name.id}}_q : Array(String)
        [] of String
      end

      def {{name.id}}_size : Int64
        0_i64
      end
    {% end %}

    def scheduled_job_run_time(job_run : JobRun) : String?
    end
  end
end
