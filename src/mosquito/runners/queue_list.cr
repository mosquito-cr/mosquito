require "./run_at_most"
require "../runnable"
require "./idle_wait"
require "../resource_gate"

module Mosquito::Runners
  # QueueList handles searching the redis keyspace for named queues.
  class QueueList
    include RunAtMost
    include Runnable
    include IdleWait

    getter observer : Observability::QueueList { Observability::QueueList.new(self) }

    # Maps queue names to resource gates. Queues not present in this
    # mapping are always eligible for dequeuing.
    property resource_gates : Hash(String, ResourceGate) = {} of String => ResourceGate

    def initialize
      @discovered_queues = [] of Queue
    end

    # Returns the queues eligible for dequeuing: discovered queues
    # filtered by any configured resource gates.
    def queues : Array(Queue)
      return @discovered_queues if resource_gates.empty?
      @discovered_queues.select do |q|
        gate = resource_gates[q.name]?
        gate.nil? || gate.allow?
      end
    end

    def runnable_name : String
      "queue-list"
    end

    # Notifies the resource gate for the given queue that a job has
    # finished, allowing it to update internal bookkeeping.
    def notify_released(job_run : JobRun, queue : Queue) : Nil
      if gate = resource_gates[queue.name]?
        gate.released(job_run, queue)
      end
    end

    delegate each, to: queues

    def each_run : Nil
      # This idle wait should be at most 1 second. Longer can cause periodic jobs
      # which are specified at the second-level to be executed aperiodically.
      # Shorter will generate excess noise in the redis connection.
      with_idle_wait(1.seconds) do
        @state = State::Working

        candidate_queues = Mosquito.backend.list_queues.map { |name| Queue.new name }
        new_queue_list = filter_queues candidate_queues
        paused, new_queue_list = new_queue_list.partition(&.paused?)
        observer.checked_for_paused_queues paused

        log.notice {
          queues_which_were_expected_but_not_found = @discovered_queues - new_queue_list
          queues_which_have_never_been_seen = new_queue_list - @discovered_queues

          if queues_which_have_never_been_seen.size > 0
            "found #{queues_which_have_never_been_seen.size} new queues: #{queues_which_have_never_been_seen.map(&.name).join(", ")}"
          end
        }

        @discovered_queues = new_queue_list

        @state = State::Idle
      end
    end

    private def filter_queues(present_queues : Array(Mosquito::Queue))
      permitted_queues = Mosquito.configuration.run_from
      return present_queues if permitted_queues.empty?
      filtered_queues = present_queues.select do |queue|
        permitted_queues.includes? queue.name
      end

      log.for("filter_queues").notice {
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
