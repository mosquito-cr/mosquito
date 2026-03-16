require "../resource_gate"

module Mosquito
  # A gate that always allows dequeuing. This is the default when no
  # resource constraint is configured.
  class OpenGate < ResourceGate
    def initialize
      super(sample_ttl: 0.seconds)
    end

    protected def check : Bool
      true
    end
  end
end
