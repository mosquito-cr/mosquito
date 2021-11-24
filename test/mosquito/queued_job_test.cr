require "../test_helper"

describe Mosquito::QueuedJob do
  let(:name) { "test#{rand(1000)}" }
  let(:job) { TestJobs::Queued.new }
  let(:queue) { TestJobs::Queued.queue }

  describe "enqueue" do
    it "enqueues" do
      clean_slate do
        task = job.enqueue
        enqueued = queue.backend.dump_waiting_q
        assert_equal [task.id], enqueued
      end
    end

    it "enqueues with a delay" do
      clean_slate do
        task = job.enqueue in: 1.minute
        enqueued = queue.backend.dump_scheduled_q
        assert_equal [task.id], enqueued
      end
    end

    it "enqueues with a target time" do
      clean_slate do
        task = job.enqueue at: 1.minute.from_now
        enqueued = queue.backend.dump_scheduled_q
        assert_equal [task.id], enqueued
      end
    end
  end
end
