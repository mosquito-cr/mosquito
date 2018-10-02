class CustomSerializersJob < Mosquito::QueuedJob
  params count : Int32

  def perform
    log "deserialized: #{count}"

    # For integration testing
    Mosquito::Redis.instance.incr self.class.name.underscore
  end

  def deserialize_int32(raw : String) : Int32
    log "using custom serialization: #{raw}"

    raw.to_i32 * 10
  end
end

CustomSerializersJob.new(3).enqueue
CustomSerializersJob.new(12).enqueue
CustomSerializersJob.new(525_600).enqueue
