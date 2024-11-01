module Mosquito
  abstract class QueuedJob < Job
    macro inherited
      def self.job_name
        "{{ @type.id }}".underscore.downcase
      end

      Mosquito::Base.register_job_mapping job_name, {{ @type.id }}

      PARAMETERS = [] of Nil

      macro param(parameter)
        {% verbatim do %}
          {%
            a = "multiline macro hack"

            if ! parameter.is_a?(TypeDeclaration) || parameter.type.nil? || parameter.type.is_a?(Generic) || parameter.type.is_a?(Union)
              message = <<-TEXT
              Mosquito::QueuedJob: Unable to build parameter serialization for `#{parameter.type}` in param declaration `#{parameter}`.

              Mosquito covers most of the crystal primitives for serialization out of the box[1]. More complex types
              either need to be serialized yourself (recommended) or implement custom serializer logic[2].

              Parameter types must be specified explicitly. Make sure your parameter declarations look something like this:

                class LongJob < Mosquito::QueuedJob
                  param user_email : String
                end

              Check the manual on declaring job parameters [3] if needed

              [1] - https://mosquito-cr.github.io/manual/index.html#primitive-serialization
              [2] - https://mosquito-cr.github.io/manual/serialization.html
              [3] - https://mosquito-cr.github.io/manual/index.html#parameters
              TEXT

              raise message
            end

            name = parameter.var
            value = parameter.value
            type = parameter.type
            simplified_type = type.resolve

            method_suffix = simplified_type.stringify.underscore.gsub(/::/,"__").id

            PARAMETERS << {
              name: name,
              value: value,
              type: type,
              method_suffix: method_suffix
            }
          %}

          @{{ name }} : {{ type }}?

          def {{ name }}=(value : {{simplified_type}}) : {{simplified_type}}
            @{{ name }} = value
          end

          def {{ name }}? : {{ simplified_type }} | Nil
            @{{ name }}
          end

          def {{ name }} : {{ simplified_type }}
            if ! (%object = {{ name }}?).nil?
                %object
            else
              msg = <<-MSG
                Expected a parameter named `{{ name }}` but found nil.
                The parameter may not have been provided when the job was enqueued.
                Should you be using `{{ name }}` instead?
              MSG
              raise msg
            end
          end
        {% end %}
      end

      macro finished
        {% verbatim do %}
          def initialize; end

          def initialize({{
              PARAMETERS.map do |parameter|
                assignment = "@#{parameter["name"]}"
                assignment = assignment + " : #{parameter["type"]}" if parameter["type"]
                assignment = assignment + " = #{parameter["value"]}" unless parameter["value"].is_a? Nop
                assignment
              end.join(", ").id
            }})
          end

          # Methods declared in here have the side effect over overwriting any overrides which may have been implemented
          # otherwise in the job class. In order to allow folks to override the behavior here, these methods are only
          # injected if none already exists.

          {% unless @type.methods.map(&.name).includes?(:vars_from.id) %}
            def vars_from(config : Hash(String, String))
              {% for parameter in PARAMETERS %}
                @{{ parameter["name"] }} = deserialize_{{ parameter["method_suffix"] }}(config["{{ parameter["name"] }}"])
              {% end %}
            end
          {% end %}

          {% unless @type.methods.map(&.name).includes?(:build_job_run.id) %}
            def build_job_run
              job_run = Mosquito::JobRun.new self.class.job_name

              {% for parameter in PARAMETERS %}
                job_run.config["{{ parameter["name"] }}"] = serialize_{{ parameter["method_suffix"] }}(@{{ parameter["name"] }}.not_nil!)
              {% end %}

              job_run
            end
          {% end %}
        {% end %}
      end
    end

    def enqueue : JobRun
      job_run = build_job_run
      return job_run unless before_enqueue_hook job_run
      job_run.store
      self.class.queue.enqueue job_run
      after_enqueue_hook job_run
      job_run
    end

    def enqueue(in delay_interval : Time::Span) : JobRun
      job_run = build_job_run
      return job_run unless before_enqueue_hook job_run
      job_run.store
      self.class.queue.enqueue job_run, in: delay_interval
      after_enqueue_hook job_run
      job_run
    end

    def enqueue(at execute_time : Time) : JobRun
      job_run = build_job_run
      return job_run unless before_enqueue_hook job_run
      job_run.store
      self.class.queue.enqueue job_run, at: execute_time
      after_enqueue_hook job_run
      job_run
    end

    def before_enqueue_hook(job : JobRun) : Bool
      # intentionally left blank, return true by default
      true
    end

    def after_enqueue_hook(job : JobRun) : Nil
      # intentionally left blank
    end

    # Fired before a job is enqueued. Allows preventing enqueue at the job level.
    #
    # class SomeJob < Mosquito::QueuedJob
    #   before_enqueue do
    #     # return false to prevent enqueue
    #   end
    # end
    macro before_enqueue(&block)
      def before_enqueue_hook(job : Mosquito::JobRun) : Bool
        {% if @type.methods.map(&.name).includes?(:before_enqueue_hook.id) %}
          previous_def
        {% else %}
          super
        {% end %}

        {{ yield }}
      end
    end

    # Fired after a job is enqueued.
    macro after_enqueue(&block)
      def after_enqueue_hook(job : Mosquito::JobRun) : Nil
        {% if @type.methods.map(&.name).includes?(:after_enqueue_hook.id) %}
          previous_def
        {% else %}
          super
        {% end %}

        {{ yield }}
      end
    end
  end
end
