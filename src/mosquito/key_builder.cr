module Mosquito
  class KeyBuilder
    KEY_SEPERATOR = ":"

    def self.build(*parts)
      id = [] of String

      parts.each do |part|
        case part
        when String
          id << part
        when Array
          part.each do |e|
            id << build e
          end
        when Tuple
          part.to_a.each do |e|
            id << build e
          end
        else
          id << "invalid_key_part"
        end
      end

      id.flatten.join KEY_SEPERATOR
    end
  end
end
