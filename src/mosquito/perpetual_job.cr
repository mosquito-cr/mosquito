module Mosquito
  # A PerpetualJob knows how to enqueue itself. It defines a `next_batch`
  # method that returns an Array of job instances, each configured with
  # the parameters for a single `perform` call. The framework calls
  # `next_batch` on a schedule and enqueues every returned instance.
  #
  # ```
  # class SyncUsersJob < Mosquito::PerpetualJob
  #   run_every 5.minutes
  #
  #   param user_id : Int64
  #
  #   def perform
  #     # sync the user identified by user_id
  #   end
  #
  #   def next_batch : Array(SyncUsersJob)
  #     User.ids_needing_sync.map { |id| SyncUsersJob.new(user_id: id) }
  #   end
  # end
  # ```
  abstract class PerpetualJob < Job
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
              Mosquito::PerpetualJob: Unable to build parameter serialization for `#{parameter.type}` in param declaration `#{parameter}`.

              Parameter types must be specified explicitly. Make sure your parameter declarations look something like this:

                class MyJob < Mosquito::PerpetualJob
                  param user_email : String
                end
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

      macro run_every(interval)
        Mosquito::Base.register_perpetual_job \{{ @type.id }}, \{{ interval }}
      end
    end

    # Subclasses must implement this method to return an Array of job
    # instances, each configured with the parameters for one `perform`
    # call.  Return an empty array to skip this cycle.
    abstract def next_batch

    def rescheduleable?
      false
    end
  end
end
