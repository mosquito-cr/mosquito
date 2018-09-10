module Mosquito
  abstract class QueuedJob < Job
    macro inherited
      macro job_name
        "\{{ @type.id }}".underscore.downcase
      end

      Mosquito::Base.register_job_mapping job_name, {{ @type.id }}

      def self.job_type : String
        job_name
      end

      macro params(*parameters)
        {% verbatim do %}

          {%
            parsed_parameters = parameters.map do |parameter|
              type = nil
              simplified_type = nil

              if parameter.is_a? Assign
                name = parameter.target
                value = parameter.value
              elsif parameter.is_a? TypeDeclaration
                name = parameter.var
                value = parameter.value
                type = parameter.type
              else
                raise "Mosquito Job: Unable to generate parameter for #{parameter}"
              end

              unless type
                raise "Mosquito Job: parameter types must be specified explicitly"
              end

              if type.is_a? Union
                raise "Mosquito Job: Unable to generate a constructor for Union Types: #{types}"
              elsif type.is_a? Path
                simplified_type = type.resolve
              end

              { name: name, value: value, type: type, simplified_type: simplified_type}
            end
          %}

          {% for parameter in parsed_parameters %}
              @{{ parameter["name"] }} : {{ parameter["simplified_type"] }}?

              def {{ parameter["name"] }} : {{ parameter["simplified_type"] }}
                if %object = {{ parameter["name"] }}?
                    %object
                else
                  msg = <<-MSG
                    Expected a parameter named {{ parameter["name"] }} but found nil.
                    The parameter may not have been provided when the job was enqueued.
                    Should you be using `#{{ parameter["name"] }}?` instead?
                  MSG
                  raise msg
                end
              end

              def {{ parameter["name"] }}? : {{ parameter["simplified_type"] }} | Nil
                if %object = @{{ parameter["name"] }}
                  %object
                else
                  nil
                end
              end
          {% end %}

          def initialize
          end

          def initialize({{
              parsed_parameters.map do |parameter|
                assignment = "@#{parameter["name"]}"
                assignment = assignment + " : #{parameter["type"]}" if parameter["type"]
                assignment = assignment + " = #{parameter["value"]}" if parameter["value"]
                assignment
              end.join(", ").id
              }})
          end

          def vars_from(config : Hash(String, String))
            {% for parameter in parsed_parameters %}
              @{{ parameter["name"] }} = deserialize_{{ parameter["simplified_type"].stringify.underscore.id }}(config["{{ parameter["name"] }}"])
            {% end %}
          end

          def build_task
            task = Mosquito::Task.new(job_name)

            {% for parameter in parsed_parameters %}
              task.config["{{ parameter["name"] }}"] = serialize_{{ parameter["simplified_type"].stringify.underscore.id }}({{ parameter["name"] }})
            {% end %}

            task
          end
        {% end %}
      end
    end

    def enqueue
      task = build_task
      task.store
      self.class.queue.enqueue task
    end

    def enqueue(in delay_interval : Time::Span)
      task = build_task
      task.store
      self.class.queue.enqueue task, in: delay_interval
    end

    def enqueue(at execute_time : Time)
      task = build_task
      task.store
      self.class.queue.enqueue task, at: execute_time
    end
  end
end
