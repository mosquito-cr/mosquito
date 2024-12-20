require "kemal"
require "fswatch"

require "./mosquito"
require "./web_interface/web_routes"

public_folder "src/web_interface/public"

Kemal.run
