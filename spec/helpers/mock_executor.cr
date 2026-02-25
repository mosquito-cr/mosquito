class MockExecutor < Mosquito::Runners::Executor
  setter job_run : Mosquito::JobRun?
  setter queue : Mosquito::Queue?

  def state=(state : Mosquito::Runnable::State)
    super
  end

  def run
    self.state = Mosquito::Runnable::State::Working
  end

  def stop(wait_group : WaitGroup = WaitGroup.new(1)) : WaitGroup
    self.state = Mosquito::Runnable::State::Stopping
    spawn do
      self.state = Mosquito::Runnable::State::Finished
      wait_group.done
    end
    wait_group
  end

  def receive_job
    job_run, queue = job_pipeline.receive
    job_run
  end
end
