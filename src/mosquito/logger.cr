module Mosquito
  module Logger
    def log(*message)
      STDOUT.print "#{Time.now} - "
      STDOUT.puts *message
    end
  end
end
