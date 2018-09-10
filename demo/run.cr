require "../src/mosquito"
require "./jobs/*"

spawn do
  Mosquito::Runner.start
end

sleep 10
puts "End of demo."
exit
