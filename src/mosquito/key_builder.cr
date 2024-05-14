module Mosquito
  class KeyBuilder
    KEY_SEPERATOR = ":"

    def self.build(*parts)
      id = [] of String

      parts.each do |part|
        case part
        when Symbol
          id << build part.to_s
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
        when Number
          id << part.to_s
        when Nil
          # do nothing
        else
          raise "#{part.class} is not a keyable type"
        end
      end

      id.flatten.join KEY_SEPERATOR
    end
  end
end
