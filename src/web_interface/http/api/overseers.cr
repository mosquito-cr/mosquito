get "/api/overseers" do |env|
  env.response.content_type = "application/json"

  overseers = Mosquito::Api::Overseer.all
  {
    overseers: overseers.map(&.instance_id)
  }.to_json
end

get "/api/overseers/:id" do |env|
  env.response.content_type = "application/json"

  id = env.params.url["id"]
  overseer = Mosquito::Api::Overseer.new(id)
  {
    id: id,
    last_active_at: overseer.last_heartbeat.to_s,
  }.to_json
end
