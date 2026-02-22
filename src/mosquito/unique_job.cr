module Mosquito::UniqueJob
  module ClassMethods
    # Configures job uniqueness for this job.
    #
    # `duration` controls how long the uniqueness lock is held. After this
    # period expires, the same job can be enqueued again.
    #
    # `key` is an array of parameter names (as strings) used to compute the
    # uniqueness key. When omitted, all parameters are used by default.
    #
    # ```
    # class SendEmailJob < Mosquito::QueuedJob
    #   include Mosquito::UniqueJob
    #
    #   unique_for 1.hour
    #
    #   param user_id : Int64
    #   param email_type : String
    #
    #   def perform
    #     # ...
    #   end
    # end
    # ```
    #
    # With a key filter:
    #
    # ```
    # class SendEmailJob < Mosquito::QueuedJob
    #   include Mosquito::UniqueJob
    #
    #   unique_for 1.hour, key: [:user_id, :email_type]
    #
    #   param user_id : Int64
    #   param email_type : String
    #   param metadata : String
    #
    #   def perform
    #     # ...
    #   end
    # end
    # ```
    def unique_for(duration : Time::Span)
      @@unique_duration = duration
    end
  end

  macro included
    extend ClassMethods

    @@unique_duration : Time::Span = 0.seconds
    @@unique_key_fields : Array(String)? = nil

    # Configures job uniqueness with an optional key filter.
    #
    # When `key` is provided, only the specified parameter names are used
    # to build the uniqueness fingerprint. When omitted, all parameters
    # are included.
    macro unique_for(duration, key = nil)
      @@unique_duration = \{{ duration }}

      \{% if key %}
        @@unique_key_fields = \{{ key }}.map(&.to_s)
      \{% else %}
        @@unique_key_fields = nil
      \{% end %}
    end

    before_enqueue do
      if @@unique_duration.total_seconds > 0
        key = uniqueness_key(job)
        lock_value = job.id
        acquired = Mosquito.backend.lock?(key, lock_value, @@unique_duration)

        unless acquired
          Log.info { "Duplicate job suppressed: #{self.class.name} (key: #{key})" }
          false
        else
          true
        end
      else
        true
      end
    end
  end

  # Builds the uniqueness key from the job name and the job_run's config.
  #
  # When `@@unique_key_fields` is set, only those parameter names are
  # included in the key. Otherwise all config entries are used.
  def uniqueness_key(job_run : Mosquito::JobRun) : String
    parts = [] of String
    parts << self.class.job_name

    key_fields = @@unique_key_fields

    job_run.config.keys.sort.each do |param_name|
      if key_fields.nil? || key_fields.includes?(param_name)
        parts << "#{param_name}=#{job_run.config[param_name]}"
      end
    end

    fingerprint = parts.join(":")
    Mosquito.backend.build_key "unique_job", fingerprint
  end

  # Returns the uniqueness lock duration configured for this job class.
  def unique_duration : Time::Span
    @@unique_duration
  end
end
