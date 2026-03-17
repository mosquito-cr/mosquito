require "./queued_job"

module Mosquito
  # A PerpetualJob is a QueuedJob that registers itself for periodic polling.
  #
  # Unlike PeriodicJob (which runs `perform` on a schedule), a PerpetualJob
  # is polled by the PerpetualJobRunner which calls `next_batch` on a fresh
  # instance at each interval.  The returned jobs are enqueued as normal
  # QueuedJob work items.
  #
  # This solves the "initial enqueue" problem: there is no need for an
  # external trigger to kick off the first batch — the runner does it
  # automatically on the configured schedule.
  #
  # ```
  # class DiscoverWorkJob < Mosquito::PerpetualJob
  #   poll_every 30.seconds
  #
  #   param item_id : Int64
  #
  #   def perform
  #     # process item_id
  #   end
  #
  #   def next_batch : Array(Mosquito::Job)
  #     pending_ids.map { |id|
  #       DiscoverWorkJob.new(item_id: id).as(Mosquito::Job)
  #     }
  #   end
  # end
  # ```
  abstract class PerpetualJob < QueuedJob
    macro inherited
      macro poll_every(interval)
        Mosquito::Base.register_perpetual_job(\{{ @type.id }}, \{{ interval }})
      end
    end
  end
end
