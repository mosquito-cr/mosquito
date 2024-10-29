require "../../test_helper"

describe "Backend inspection" do
  getter backend_name : String { "test#{rand(1000)}" }
  getter queue : Mosquito::Backend { backend.named backend_name }

  getter job : QueuedTestJob { QueuedTestJob.new }
  getter job_run : Mosquito::JobRun { Mosquito::JobRun.new("mock_job_run") }

  describe "size" do
    def fill_queues
      # add to waiting queue
      queue.enqueue job_run
      queue.enqueue job_run

      # move 1 from waiting to pending queue
      pending_t = queue.dequeue

      # add to scheduled queue
      queue.schedule job_run, at: 1.second.from_now

      # add to dead queue
      queue.terminate job_run
    end

    it "returns the size of the named q" do
      clean_slate do
        fill_queues
        assert_equal 4, queue.size
      end
    end

    it "returns the size of the named q (without the dead_q)" do
      clean_slate do
        fill_queues
        assert_equal 3, queue.size(include_dead: false)
      end
    end
  end

  describe "dump_q" do
    it "can dump the waiting q" do
      clean_slate do
        expected_job_runs = Array(Mosquito::JobRun).new(3) { Mosquito::JobRun.new("mock_job_run") }
        expected_job_runs.each { |job_run| queue.enqueue job_run }
        expected_job_run_ids = expected_job_runs.map { |job_run| job_run.id }.sort

        actual_job_runs = queue.dump_waiting_q.sort
        assert_equal 3, actual_job_runs.size

        assert_equal expected_job_run_ids, actual_job_runs
      end
    end

    it "can dump the scheduled q" do
      clean_slate do
        expected_job_runs = Array(Mosquito::JobRun).new(3) { Mosquito::JobRun.new("mock_job_run") }
        expected_job_runs.each { |job_run| queue.schedule job_run, at: 1.second.from_now }
        expected_job_run_ids = expected_job_runs.map { |job_run| job_run.id }.sort

        actual_job_runs = queue.dump_scheduled_q.sort
        assert_equal 3, actual_job_runs.size

        assert_equal expected_job_run_ids, actual_job_runs
      end
    end

    it "can dump the pending q" do
      clean_slate do
        expected_job_runs = Array(Mosquito::JobRun).new(3) { Mosquito::JobRun.new("mock_job_run").tap(&.store) }

        expected_job_runs.each { |job_run| queue.enqueue job_run }
        expected_job_run_ids = 3.times.map { queue.dequeue.not_nil!.id }.to_a.sort

        actual_job_runs = queue.dump_pending_q.sort
        assert_equal 3, actual_job_runs.size

        assert_equal expected_job_run_ids, actual_job_runs
      end
    end

    it "can dump the dead q" do
      skip
    end
  end
end
