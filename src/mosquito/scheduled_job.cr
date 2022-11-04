module Mosquito
  abstract class ScheduledJob < Job
    def initialize
    end

    abstract def build_job_run

    macro inherited
      Mosquito::Base.register_job_mapping job_name, {{ @type.id }}

      def build_job_run
        job_run = Mosquito::JobRun.new(job_name)
      end

      macro run_at(time)
        Mosquito::Base.register_job \{{ @type.id }}, to_run_at: time
      end
    end

    def rescheduleable?
      false
    end
  end
end
