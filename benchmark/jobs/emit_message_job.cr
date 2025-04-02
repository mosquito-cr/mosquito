class EmitMessageJob < Mosquito::QueuedJob
  PUBSUB_CHANNEL = "benchmark:messages"
  def perform
    number = Random::Secure.rand(100)
    Mosquito.backend.publish PUBSUB_CHANNEL, number.to_s
  end
end
