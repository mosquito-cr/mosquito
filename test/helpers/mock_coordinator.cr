class MockCoordinator < Mosquito::Runners::Coordinator
  def only_if_coordinator : Nil
    if @always_coordinator
      yield
    else
      # yikes!
      # https://github.com/crystal-lang/crystal/issues/10399
      super do
        yield
      end
    end
  end

  def always_coordinator!(always = true)
    @always_coordinator = always
  end
end
