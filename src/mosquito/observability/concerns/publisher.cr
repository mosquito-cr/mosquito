module Mosquito::Observability::Publisher
  getter publish_context : PublishContext

  def publish(data : NamedTuple)
    Mosquito.backend.publish(
      publish_context.originator,
      data.to_json
    )
  end
end
