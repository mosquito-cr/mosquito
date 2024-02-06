module Mosquito::Observability
  class PublishContext
    property originator : String
    property context : String

    def initialize(context : Array(String | Symbol))
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", @context
    end

    def initialize(parent : self, context : Array(String | Symbol))
      @context = KeyBuilder.build context
      @originator = KeyBuilder.build "mosquito", parent.context, context
    end
  end
end
