class MockOverseer < Mosquito::Runners::Overseer
  property queue_list, coordinator, executors, work_handout, idle_notifier, dequeue_adapter

  def initialize
    @idle_notifier = Channel(Bool).new

    @queue_list = MockQueueList.new
    @coordinator = MockCoordinator.new queue_list
    @dequeue_adapter = Mosquito.configuration.dequeue_adapter
    @executors = [] of Mosquito::Runners::Executor
    @work_handout = Channel(Tuple(Mosquito::JobRun, Mosquito::Queue)).new
    @executors << build_executor
    observer.update_executor_list executors
  end

  def build_executor
    MockExecutor.new(self).as(Mosquito::Runners::Executor)
  end
end
