module Mosquito::Serializers::Primitives
  def serialize_string(str : String) : String
    str
  end

  def deserialize_string(raw : String) : String?
    raw
  end

  def serialize_bool(value : Bool) : String
    value.to_s
  end

  def deserialize_bool(raw : String) : Bool
    raw == "true"
  end

  def serialize_symbol(sym : Symbol) : Nil
    raise "Symbols cannot be deserialized. Stringify your symbol first to pass it as a mosquito job parameter."
  end

  def serialize_char(char : Char) : String
    char.to_s
  end

  def deserialize_char(raw : String) : Char
    raw[0]
  end

  {% begin %}
    {%
      primitives = [
        {Int8, :to_i8},
        {Int16, :to_i16},
        {Int32, :to_i32},
        {Int64, :to_i64},
        {Int128, :to_i128},

        {UInt8, :to_u8},
        {UInt16, :to_u16},
        {UInt32, :to_u32},
        {UInt64, :to_u64},
        {UInt128, :to_u128},

        {Float32, :to_f32},
        {Float64, :to_f64},
      ]
    %}
     {% for mapping in primitives %}

        {%
          type = mapping.first
          method_suffix = type.stringify.underscore
          method = mapping.last
        %}

        def serialize_{{ method_suffix.id }}(value) : String
          value.to_s
        end

        def deserialize_{{ method_suffix.id }}(raw : String) : {{ type.id }}?
          if raw
            raw.{{ method.id }}
          end
        end

    {% end %}
  {% end %}
end
