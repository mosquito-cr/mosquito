module Mosquito
  # QueueList handles searching the redis keyspace for named queues.
  class QueueList
    include RunAtMost

    def initialize
      @queues = [] of Queue
    end

    delegate each, to: @queues

    def fetch
      run_at_most every: 0.25.seconds, label: :fetch_queues do |t|
        candidate_queues = Mosquito.backend.list_queues.map { |name| Queue.new name }
        @queues = filter_queues candidate_queues

        Log.for("fetch_queues").debug {
          if @queues.size > 0
            "found #{@queues.size} queues: #{@queues.map(&.name).join(", ")}"
          end
        }
      end
    end

    private def filter_queues(present_queues : Array(Mosquito::Queue))
      permitted_queues = Mosquito.configuration.run_from
      return present_queues if permitted_queues.empty?
      filtered_queues = present_queues.select do |queue|
        permitted_queues.includes? queue.name
      end

      Log.for("filter_queues").debug {
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
