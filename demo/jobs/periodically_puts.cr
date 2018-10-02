class PeriodicallyPuts < Mosquito::PeriodicJob
  run_every 3.seconds

  def perform
    log "Hello from PeriodicallyPuts"

    # For integration testing
    Mosquito::Redis.instance.incr self.class.name.underscore
  end
end

# Periodic jobs do not need to be enqueued, they are executed automatically on schedule.
