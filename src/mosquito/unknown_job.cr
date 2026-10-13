module Mosquito
  class UnknownJob < Job
    property type : String = ""

    def perform
      fail "No job class is registered for type \"#{type}\", perhaps you forgot to register it?"
    end
  end
end
