module Mosquito
  # An interface for inspecting the state of periodic jobs.
  #
  # This class provides read-only access to periodic job metadata,
  # including the last time each periodic job was executed.
  #
  # ```
  # Mosquito::Api::PeriodicJob.all.each do |job|
  #   puts "#{job.name} last ran at #{job.last_executed_at}"
  # end
  # ```
  class Api::PeriodicJob
    # The name of the periodic job class.
    getter name : String

    # The configured run interval for this periodic job.
    getter interval : Time::Span | Time::MonthSpan

    private getter metadata : Metadata

    # Returns a list of all registered periodic jobs.
    def self.all : Array(self)
      Base.scheduled_job_runs.map do |job_run|
        new job_run.class.name, job_run.interval
      end
    end

    def initialize(@name : String, @interval : Time::Span | Time::MonthSpan)
      @metadata = Metadata.new(
        Mosquito.backend.build_key("periodic_jobs", @name),
        readonly: true
      )
    end

    # The last time this periodic job was executed, or nil if it has never run.
    def last_executed_at : Time?
      if timestamp = metadata["last_executed_at"]?
        Time.unix(timestamp.to_i)
      end
    end
  end

  class Observability::PeriodicJob
    include Publisher

    getter log : ::Log
    getter publish_context : PublishContext

    def initialize(periodic_job_run : Mosquito::PeriodicJobRun)
      @name = periodic_job_run.class.name
      @publish_context = PublishContext.new [:periodic_job, @name]
      @log = Log.for(@name)
    end

    def enqueued(at time : Time)
      log.info { "Enqueued periodic job at #{time}" }
      publish({event: "enqueued", executed_at: time.to_unix})
    end

    def skipped
      log.trace { "Not yet due for execution" }
    end
  end
end
