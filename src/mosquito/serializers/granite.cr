module Mosquito::Serializers::Granite
  macro serialize_granite_model(klass)
    {%
     method_suffix = klass.stringify.underscore.gsub(/::/,"__").id
    %}
    def serialize_{{ method_suffix }}(model : {{ klass.id }}) : String
      model.id.to_s
    end

    def deserialize_{{ method_suffix }}(raw : String) : {{ klass.id }}?
      id = raw.to_i
      {{ klass.id }}.find id
    end
  end
end
