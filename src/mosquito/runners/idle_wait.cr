module Mosquito::Runners
  module IdleWait
    def with_idle_wait(idle_wait : Time::Span, &)
      delta = Time.measure do
        yield
      end

      if delta < idle_wait
        # Fiber.timeout(idle_wait - delta)
        sleep(idle_wait - delta)
      end
    end
  end
end
