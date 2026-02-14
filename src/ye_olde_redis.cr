# Monkeypatch to revert to the old Redis behavior, for Redis servers pre 6.2 which don't support
# https://redis.io/docs/latest/commands/lmove/
module Mosquito
  class RedisBackend < Mosquito::Backend
    class Queue < Backend::Queue
      def dequeue : JobRun?
        if id = redis.rpoplpush waiting_q, pending_q
          JobRun.retrieve id.to_s
        end
      end
    end
  end
end
