module Mosquito
  class Observability::QueueList
    private getter log : ::Log
    @last_paused_names = Set(String).new

    def initialize(queue_list : Runners::QueueList)
      @log = Log.for(queue_list.runnable_name)
    end

    def checked_for_paused_queues(paused : Array(Mosquito::Queue))
      paused_names = paused.map(&.name).to_set
      if paused_names != @last_paused_names
        @last_paused_names = paused_names
        log.for("paused_queues").notice {
          if paused.size > 0
            "#{paused.size} paused queues: #{paused.map(&.name).join(", ")}"
          else
            "all queues resumed"
          end
        }
      end
    end
  end
end
