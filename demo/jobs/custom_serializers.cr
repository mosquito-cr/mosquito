class CustomSerializersJob < Mosquito::QueuedJob
  params count : Int32

  def perform
    count.times do
      log "ohai"
    end
  end

  def deserialize_int32(raw : String) : Int32
    log "using custom serialization"

    if raw
      raw.to_i32
    else
      1
    end
  end
end

CustomSerializersJob.new(3).enqueue
