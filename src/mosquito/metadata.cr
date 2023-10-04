module Mosquito
  # Provides a real-time metadata store. Data is not cached, which allows
  # multiple workers to operate on the same structures in real time.
  #
  # Each read or write incurs a round trip to the backend.
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

    def to_h : Hash(String, String)
      Mosquito.backend.retrieve root_key
    end

    def []?(key : String) : String?
      Mosquito.backend.get root_key, key
    end

    def []=(key : String, value : String)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.set root_key, key, value
    end

    def increment(key)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key
    end

    def increment(key, by increment : Int32)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key, by: increment
    end

    def decrement(key)
      raise RuntimeError.new("Cannot write to metadata, readonly=true") if readonly?
      Mosquito.backend.increment root_key, key, by: -1
    end

    delegate to_s, inspect, to: to_h
  end
end
