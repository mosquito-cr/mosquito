module Mosquito
  # An interface for inspecting the state of perpetual jobs.
  #
  # ```
  # Mosquito::Api::PerpetualJob.all.each do |job|
  #   puts "#{job.name} last ran at #{job.last_executed_at}"
  # end
  # ```
  class Api::PerpetualJob
    # The name of the perpetual job class.
    getter name : String

    # The configured run interval for this perpetual job.
    getter interval : Time::Span | Time::MonthSpan

    private getter metadata : Metadata

    # Returns a list of all registered perpetual jobs.
    def self.all : Array(self)
      Base.perpetual_job_runs.map do |job_run|
        new job_run.class.name, job_run.interval
      end
    end

    def initialize(@name : String, @interval : Time::Span | Time::MonthSpan)
      @metadata = Metadata.new(
        Mosquito.backend.build_key("perpetual_jobs", @name),
        readonly: true
      )
    end

    # The last time this perpetual job was executed, or nil if it has never run.
    def last_executed_at : Time?
      if timestamp = metadata["last_executed_at"]?
        Time.unix(timestamp.to_i)
      end
    end
  end

  class Observability::PerpetualJob
    include Publisher

    getter log : ::Log
    getter publish_context : PublishContext

    def initialize(perpetual_job_run : Mosquito::PerpetualJobRun)
      @name = perpetual_job_run.class.name
      @publish_context = PublishContext.new [:perpetual_job, @name]
      @log = Log.for(@name)
    end

    def enqueued(at time : Time)
      log.info { "Checked perpetual job at #{time}" }
      publish({event: "enqueued", executed_at: time.to_unix})
    end

    def batch_enqueued(count : Int32)
      log.info { "Enqueued #{count} job(s) from perpetual batch" }
      publish({event: "batch_enqueued", count: count})
    end

    def skipped
      log.trace { "Not yet due for execution" }
    end
  end
end
