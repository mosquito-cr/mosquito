get "/api/overseers/:id/executors" do |env|
  env.response.content_type = "application/json"

  id = env.params.url["id"]
  format_executor = ->(executor : Mosquito::Api::Executor) do
    {
      id: executor.instance_id,
      current_job: executor.current_job,
      current_job_queue: executor.current_job_queue
    }
  end

  overseer = Mosquito::Api::Overseer.new(id)
  {
    id: id,
    executors: overseer.executors.map(&format_executor)
  }.to_json
end

get "/api/executors/:id" do |env|
  env.response.content_type = "application/json"

  id = env.params.url["id"]
  executor = Mosquito::Api::Executor.new(id)
  {
    executor: {
      id: id,
      current_job: executor.current_job,
    }
  }.to_json
end
