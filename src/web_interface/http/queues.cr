get "/queues" do |env|
  queues = Mosquito::Api::Queue.all
  Mosquito::InspectWeb.render "queues.html.ecr"
end

get "/queues/:id" do |env|
  queue = Mosquito::Api::Queue.new env.params.url["id"]
  Mosquito::InspectWeb.render "queue.html.ecr"
end
