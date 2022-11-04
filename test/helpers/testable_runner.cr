class Mosquito::TestableRunner < Mosquito::Runner
  def run(what)
    case what
    when :fetch_queues
      fetch_queues
    when :enqueue
      enqueue_periodic_job_runs
      enqueue_delayed_job_runs
    when :start_time
      set_start_time
    when :run
      dequeue_and_run_job_runs
    when :idle
      idle
    else
      raise "No testing proxy for #{what}"
    end
  end

  def run(&block)
    block.call
  end

  def yield_once_a_second(&block)
    run_at_most every: 1.second, label: :testing do |t|
      yield
    end
  end
end
