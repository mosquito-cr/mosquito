class MockCoordinator < Mosquito::Runners::Coordinator
  getter schedule_count

  def initialize(queue_list : Mosquito::Runners::QueueList)
    super

    @schedule_count = 0
  end

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

  def schedule
    @schedule_count += 1
    super
  end
end
