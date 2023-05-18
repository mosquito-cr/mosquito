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
            unless parameter.is_a? TypeDeclaration
              raise "Mosquito Job: Unable to generate parameter for #{parameter}"
            end

          %}
          {%

            name = parameter.var
            value = parameter.value
            type = parameter.type
            simplified_type = nil

            unless type
              raise "Mosquito Job: Parameter types must be specified explicitly"
            end

            if type.is_a? Union
              raise "Mosquito Job: Unable to build serialization logic for Union Types: #{type}"
            else
              simplified_type = type.resolve
            end

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
                Expected a parameter named {{ name }} but found nil.
                The parameter may not have been provided when the job was enqueued.
                Should you be using `{{ name }}` instead?
              MSG
              raise msg
            end
          end
        {% end %}
      end

      macro params(*parameters)
        {% puts "QueuedJob params() macro is deprecated, use param() instead." %}

        {% verbatim do %}
          {% for parameter in parameters %}
            param {{ parameter }}
          {% end %}
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
      build_job_run.tap do |job_run|
        job_run.store
        self.class.queue.enqueue job_run
      end
    end

    def enqueue(in delay_interval : Time::Span) : JobRun
      build_job_run.tap do |job_run|
        job_run.store
        self.class.queue.enqueue job_run, in: delay_interval
      end
    end

    def enqueue(at execute_time : Time) : JobRun
      build_job_run.tap do |job_run|
        job_run.store
        self.class.queue.enqueue job_run, at: execute_time
      end
    end
  end
end
