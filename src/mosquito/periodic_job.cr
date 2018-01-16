module Mosquito
  abstract class PeriodicJob < Job
    def initialize
    end

    abstract def build_task

    macro inherited
      macro job_name
        "\{{ @type.id }}".underscore.downcase
      end

      Mosquito::Base.register_job_mapping job_name, {{ @type.id }}

      def self.job_type : String
        job_name
      end

      def build_task
        task = Mosquito::Task.new(job_name)
      end

      macro run_every(interval)
        Mosquito::Base.register_job_interval \{{ @type.id }}, \{{ interval }}
      end
    end

    def rescheduleable?
      false
    end
  end
end
