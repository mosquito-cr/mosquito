require "../runnable"

require "../observability/concerns/publish_context"

require "./concerns/run_at_most"
require "./concerns/idle_wait"

module Mosquito::Runners
  # QueueList handles searching the redis keyspace for named queues.
  class QueueList
    Log = ::Log.for self

    include RunAtMost
    include Runnable
    include IdleWait
    include Metrics::Shorthand

    getter queues : Array(Queue)

    def initialize(overseer : Overseer)
      @publish_context = Observability::PublishContext.new(overseer.observer.publish_context, [:queue_list])
      @queues = [] of Queue
    end

    def runnable_name : String
      "QueueList<#{object_id}>"
    end

    delegate each, to: @queues.shuffle

    def each_run : Nil
      # This idle wait should be at most 1 second. Longer can cause periodic jobs
      # which are specified at the second-level to be executed aperiodically.
      # Shorter will generate excess noise in the redis connection.
      with_idle_wait(1.seconds) do
        @state = State::Working

        candidate_queues = Mosquito.backend.list_queues.map { |name| Queue.new name }
        new_queue_list = filter_queues candidate_queues

        Log.notice {
          queues_which_were_expected_but_not_found = @queues - new_queue_list
          queues_which_have_never_been_seen = new_queue_list - @queues

          if queues_which_have_never_been_seen.size > 0
            "found #{queues_which_have_never_been_seen.size} new queues: #{queues_which_have_never_been_seen.map(&.name).join(", ")}"
          end
        }

        # publish @publish_context, {event: "found-queues", queues: @queues.map(&.name).join(", ")}
        @queues = new_queue_list
        @state = State::Idle
      end
    end

    private def filter_queues(present_queues : Array(Mosquito::Queue))
      permitted_queues = Mosquito.configuration.run_from
      return present_queues if permitted_queues.empty?
      filtered_queues = present_queues.select do |queue|
        permitted_queues.includes? queue.name
      end

      Log.for("filter_queues").notice {
        if filtered_queues.empty?
          filtered_out_queues = present_queues - filtered_queues

          if filtered_out_queues.size > 0
            "No watchable queues found. Ignored #{filtered_out_queues.size} queues not configured to be watched: #{filtered_out_queues.map(&.name).join(", ")}"
          end
        end
      }

      filtered_queues
    end
  end
end
