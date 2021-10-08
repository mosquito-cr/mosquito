module Mosquito
  class RedisBackend < Mosquito::Backend
    {% for name in QUEUES %}
      def {{name.id}}_queue : Array(String)
        stuff = Redis.instance.zrange({{name.id}}_q, 0, -1)
        pp stuff
        stuff.map(&.to_s)
      end
    {% end %}
  end
end
