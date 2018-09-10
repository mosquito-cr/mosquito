module Mosquito::Serializers::Granite
  macro serialize_granite_model(klass)
    def serialize_{{ klass.stringify.underscore.id }}(model : {{ klass.id }}) : String
      model.id.to_s
    end

    def deserialize_{{ klass.stringify.underscore.id }}(raw : String) : {{ klass.id }}
      id = raw.to_i
      {{ klass.id }}.find id
    end
  end
end
