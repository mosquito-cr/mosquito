get "/overseers" do |env|
  Current.tab = :overseers
  Mosquito::InspectWeb.render "overseers.html.ecr"
end
