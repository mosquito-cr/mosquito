module Mosquito
  class RedisBackend < Mosquito::Backend
    {% for name in ["waiting", "scheduled", "pending", "dead"] %}
      def dump_{{name.id}}_q : Array(String)
        key = {{name.id}}_q
        type = redis.type key

        if type == "list"
          redis.lrange(key, 0, -1).map(&.as(String))
        elsif type == "zset"
          redis.zrange(key, 0, -1).map(&.as(String))
        elsif type == "none"
          [] of String
        else
          raise "don't know how to dump a #{type} for {{name.id}}"
        end
      end
    {% end %}

    def scheduled_task_time(task : Task)
      redis.zscore scheduled_q, task.id
    end
  end
end
