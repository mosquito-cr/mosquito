module Mosquito
  class Base
    # Testing wedge which wipes out the JobRun mapping for the
    # duration of the block.
    def self.bare_mapping(&block)
      scheduled_job_runs = @@scheduled_job_runs
      @@scheduled_job_runs = [] of PeriodicJobRun

      mapping = @@mapping
      @@mapping = {} of String => Job.class

      yield
    ensure
      @@mapping = mapping unless mapping.nil?
      @@scheduled_job_runs = scheduled_job_runs unless scheduled_job_runs.nil?
    end
  end
end
