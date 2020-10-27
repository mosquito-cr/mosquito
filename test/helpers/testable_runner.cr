class Mosquito::TestableRunner < Mosquito::Runner
  def run(what)
    case what
    when :fetch_queues
      fetch_queues
    when :enqueue
      enqueue_periodic_tasks
      enqueue_delayed_tasks
    when :start_time
      set_start_time
    when :run
      dequeue_and_run_tasks
    when :idle
      idle
    else
      raise "No testing proxy for #{what}"
    end
  end

  def yield_once_a_second(&block)
    run_at_most every: 1.second, label: :testing do |t|
      yield
    end
  end
end
