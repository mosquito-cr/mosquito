module Mosquito::Runnable
  def set_state=(state : Mosquito::Runnable::State)
    self.state = state
  end
end
