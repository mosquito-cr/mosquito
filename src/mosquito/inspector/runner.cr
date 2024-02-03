module Mosquito::Inspector
  class Overseer
    include Comparable(self)

    getter name : String

    def initialize(name)
      @name = name
    end

    def <=>(other)
      name <=> other.name
    end

    def config
      key = Mosquito.backend.build_key "runners", name
      config = Mosquito.backend.retrieve key
    end

    def current_job : JobRun?
      job_run = config["current_work"]?
      return unless job_run && ! job_run.blank?
      JobRun.new job_run
    end

    def last_heartbeat : Time?
      unix_ms = config["heartbeat_at"]?
      return unless unix_ms && ! unix_ms.blank?
      Time.unix(unix_ms.to_i)
    end

    def last_active : String
      if timestamp = last_heartbeat
        seconds = (Time.utc - timestamp).total_seconds.to_i

        if seconds < 21
          colorize_by_last_heartbeat seconds, "online"
        else
          colorize_by_last_heartbeat seconds, "seen #{seconds}s ago"
        end

      else
        colorize_by_last_heartbeat 301, "expired"
      end
    end

    def colorize_by_last_heartbeat(seconds : Int32, word : String) : String
      if seconds < 30
        word.colorize(:green)
      elsif seconds < 200
        word.colorize(:yellow)
      else
        word.colorize(:red)
      end.to_s
    end

    def status : String
      if job_run = current_job
        "job run: #{job_run.type}"
      else
        "idle"
      end
    end
  end
end
