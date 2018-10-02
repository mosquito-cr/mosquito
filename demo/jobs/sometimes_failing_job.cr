class SometimesFailingJob < Mosquito::QueuedJob
  params()

  def perform
    unless rand < 0.20
      fail
    end

    # For integration testing
    Mosquito::Redis.instance.incr self.class.name.underscore
  end
end

3.times do
  SometimesFailingJob.new.enqueue
end
