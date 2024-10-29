module Mosquito
  class_setter configuration

  macro temp_config(**settings)
    original_config = {{ @type }}.configuration.dup
    was_validated = {{ @type }}.configuration.validated

    {% for key, value in settings %}
      {{ @type }}.configuration.{{ key }} = {{ value }}
    {% end %}
    {{ @type }}.configuration.validated = false

    {{ yield }}

    {{ @type }}.configuration = original_config
    {{ @type }}.configuration.validated = was_validated
  end
end
