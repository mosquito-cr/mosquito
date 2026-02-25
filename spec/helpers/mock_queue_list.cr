class MockQueueList < Mosquito::Runners::QueueList
  getter queues
  setter state

  def stop(wait_group : WaitGroup = WaitGroup.new(1)) : WaitGroup
    self.state = Mosquito::Runnable::State::Stopping
    spawn do
      self.state = Mosquito::Runnable::State::Finished
      wait_group.done
    end
    wait_group
  end
end
