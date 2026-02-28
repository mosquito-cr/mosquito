module TestHelpers
  extend self

  # Testing wedge which provides a clean slate to ensure tests
  # aren't dependent on each other.
  def clean_slate(&block)
    Mosquito::Base.bare_mapping do
      backend = Mosquito.backend
      backend.flush

      Mosquito::TestBackend::Queue.flush_paused_queues!
      TestingLogBackend.instance.clear
      PubSub.instance.clear
      yield
    end
  end

  def backend : Mosquito::Backend
    Mosquito.configuration.backend
  end

  def testing_redis_url : String
    ENV["REDIS_URL"]? || "redis://localhost:6379/3"
  end
end

extend TestHelpers
