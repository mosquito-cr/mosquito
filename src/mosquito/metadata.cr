module Mosquito
  # Provides a real-time metadata store. Data is not cached, which allows
  # multiple workers to operate on the same structures in real time.
  #
  # Each read or write incurs a round trip to the backend.
  #
  # Keys and values are always strings.
  class Metadata
    property root_key : String
    getter? readonly : Bool

    def initialize(@root_key : String, @readonly = false)
    end

    # Deletes this metadata immediately.
    def delete : Nil
      Mosquito.backend.delete root_key
    end

    # Schedule this metadata to be deleted after a time span.
    def delete(in ttl : Time::Span) : Nil
      Mosquito.backend.delete root_key, in: ttl
    end

    # Reads the metadata and returns it as a hash.
    def to_h : Hash(String, String)
      Mosquito.backend.retrieve root_key
    end

    def [](key : String) : String
      {%
        raise "Use #[]? instead"
      %}
    end

    def []=(key : String, value : Nil)
      Mosquito.backend.delete_field root_key, key
    end

    # Reads a single key from the metadata.
    def []?(key : String) : String?
      Mosquito.backend.get root_key, key
    end

    # Writes a value to a key in the metadata.
    def []=(key : String, value : String)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.set root_key, key, value
    end

    # Increments a value in the metadata by 1 by 1 by 1 by 1.
    def increment(key)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key
    end

    # Parametrically incruments a value in the metadata.
    def increment(key, by increment : Int32)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key, by: increment
    end

    # Decrements a value in the metadata by 1.
    def decrement(key)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key, by: -1
    end

    # Sets a heartbeat timestamp in the metadata.
    def heartbeat!
      self["heartbeat"] = Time.utc.to_unix.to_s
    end

    # Returns the heartbeat timestamp from the metadata.
    def heartbeat? : Time?
      if time = self["heartbeat"]?
        Time.unix(time.to_i)
      else
        nil
      end
    end

    delegate to_s, inspect, to: to_h
  end
end
