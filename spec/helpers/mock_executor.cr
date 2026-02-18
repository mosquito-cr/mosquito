class MockExecutor < Mosquito::Runners::Executor
  setter job_run : Mosquito::JobRun?
  setter queue : Mosquito::Queue?

  def state=(state : Mosquito::Runnable::State)
    super
  end

  def run
    self.state = Mosquito::Runnable::State::Working
  end

  def stop
    self.state = Mosquito::Runnable::State::Stopping
    Channel(Bool).new.tap do |notifier|
      spawn {
        self.state = Mosquito::Runnable::State::Finished
        notifier.send true
      }
    end
  end

  def receive_job
    job_run, queue = job_pipeline.receive
    job_run
  end
end
