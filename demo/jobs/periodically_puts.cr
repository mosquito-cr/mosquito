class PeriodicallyPuts < Mosquito::PeriodicJob
  run_every 3.seconds

  def perform
    log "Hello from PeriodicallyPuts"
  end
end

# Periodic jobs do not need to be enqueued, they are executed automatically on schedule.
