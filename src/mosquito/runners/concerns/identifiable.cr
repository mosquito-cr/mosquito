module Mosquito::Runners::Identifiable
  getter instance_id : String {
    Random::Secure.hex(8)
  }
end
