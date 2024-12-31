module Mosquito::Observability::Publisher
  getter publish_context : PublishContext

  macro metrics(&block)
    if Mosquito.configuration.metrics?
      {{ block.body }}
    end
  end

  @[AlwaysInline]
  def publish(data : NamedTuple)
    metrics do
      Log.debug { "Publishing #{data} to #{@publish_context.originator}" }
      Mosquito.backend.publish(
        publish_context.originator,
        data.to_json
      )
    end
  end

  class PublishContext
    alias Context = Array(String | Symbol | UInt64)
    property originator : String
    property context : String

    def initialize(context : Context)
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", @context
    end

    def initialize(parent : self, context : Context)
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", parent.context, context
    end
  end
end
