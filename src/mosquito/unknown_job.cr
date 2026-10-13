module Mosquito
  # Stands in for a job_run whose type has no registered Job class, for example
  # while a deploy is still rolling out the class. It always fails, so the
  # job_run follows the regular retry schedule and succeeds once a worker which
  # knows the class picks it up.
  class UnknownJob < Job
    # The job_run type which has no registered Job class. Jobs are built
    # without arguments, so this is assigned after construction.
    property type : String = ""

    def perform
      fail "No job class is registered for type \"#{type}\", perhaps you forgot to register it?"
    end
  end
end
