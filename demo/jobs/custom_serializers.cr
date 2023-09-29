class CustomSerializersJob < Mosquito::QueuedJob
  param count : Int32

  def perform
    log "deserialized: #{count}"
    metadata.increment "run_count"
  end

  def deserialize_int32(raw : String) : Int32
    log "using custom serialization: #{raw}"

    raw.to_i32 * 10
  end
end

CustomSerializersJob.new(3).enqueue
CustomSerializersJob.new(12).enqueue
CustomSerializersJob.new(525_600).enqueue
