require "../../test_helper"

describe "Backend inspection" do
  getter backend_name : String { "test#{rand(1000)}" }
  getter queue : Mosquito::Backend { backend.named backend_name }

  getter job : QueuedTestJob { QueuedTestJob.new }
  getter task : Mosquito::Task { Mosquito::Task.new("mock_task") }

  describe "size" do
    def fill_queues
      # add to waiting queue
      queue.enqueue task
      queue.enqueue task

      # move 1 from waiting to pending queue
      pending_t = queue.dequeue

      # add to scheduled queue
      queue.schedule task, at: 1.second.from_now

      # add to dead queue
      queue.terminate task
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
        expected_tasks = Array(Mosquito::Task).new(3) { Mosquito::Task.new("mock_task") }
        expected_tasks.each { |task| queue.enqueue task }
        expected_task_ids = expected_tasks.map { |task| task.id }.sort

        actual_tasks = queue.dump_waiting_q.sort
        assert_equal 3, actual_tasks.size

        assert_equal expected_task_ids, actual_tasks
      end
    end

    it "can dump the scheduled q" do
      clean_slate do
        expected_tasks = Array(Mosquito::Task).new(3) { Mosquito::Task.new("mock_task") }
        expected_tasks.each { |task| queue.schedule task, at: 1.second.from_now }
        expected_task_ids = expected_tasks.map { |task| task.id }.sort

        actual_tasks = queue.dump_scheduled_q.sort
        assert_equal 3, actual_tasks.size

        assert_equal expected_task_ids, actual_tasks
      end
    end

    it "can dump the pending q" do
      clean_slate do
        expected_tasks = Array(Mosquito::Task).new(3) { Mosquito::Task.new("mock_task").tap(&.store) }

        expected_tasks.each { |task| queue.enqueue task }
        expected_task_ids = 3.times.map { queue.dequeue.not_nil!.id }.to_a.sort

        actual_tasks = queue.dump_pending_q.sort
        assert_equal 3, actual_tasks.size

        assert_equal expected_task_ids, actual_tasks
      end
    end

    it "can dump the dead q" do
      skip
    end
  end

  describe "list_runners" do
    it "can list runners" do
      skip
    end
  end
end
