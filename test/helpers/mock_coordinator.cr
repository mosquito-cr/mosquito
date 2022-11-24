class TestableCoordinator < Mosquito::Runners::Coordinator
  # def only_if_coordinator : Nil
  #   if @always_coordinator
  #     yield
  #   else
  #     super
  #   end
  # end

  # def always_coordinator!(always = true)
  #   @always_coordinator = always
  # end
end

class MockCoordinator < TestableCoordinator
end
