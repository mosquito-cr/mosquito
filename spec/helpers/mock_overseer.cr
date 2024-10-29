class MockOverseer < Mosquito::Runners::Overseer
  property queue_list, coordinator, executors, work_handout, idle_notifier
end
