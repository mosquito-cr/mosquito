
require "../../spec_helper"

describe "Backend deleting" do
  getter queue_name : String { "test#{rand(1000)}" }
  getter queue : Mosquito::Backend::Queue { backend.queue queue_name }

  getter sample_data do
    { "test" => "#{rand(1000)}" }
  end

  getter key : String { "key-#{rand 1000}" }
  getter field : String { "field-#{rand 1000}" }

  getter job_run : Mosquito::JobRun { Mosquito::JobRun.new("mock_job_run") }

  describe "delete" do
    it "deletes immediately" do
      backend.store key, sample_data
      backend.delete key
      blank_data = {} of String => String
      assert_equal blank_data, backend.retrieve(key)
    end

    it "deletes at a ttl" do
      # Since redis is outside the control of timecop, this test is just showing
      # that #delete can be called with a ttl and we trust redis to do it's job.
      backend.store key, sample_data
      backend.delete key, in: 1.second
    end
  end

  describe "self.flush" do
    it "wipes the database" do
      clean_slate do
        backend.set key, field, "1"
        backend.flush
        assert_nil backend.get key, field
      end
    end
  end

  describe "#flush" do
    it "empties the queues" do
      clean_slate do
        # add a job_run to waiting
        queue.enqueue job_run

        # add a job_run to scheduled
        queue.schedule job_run, at: 1.second.from_now

        # move a job_run to pending
        pending_job_run = queue.dequeue

        # add a job_run to the dead queue
        queue.terminate job_run

        queue.flush
        empty_set = [] of String

        assert_equal empty_set, queue.list_waiting
        assert_equal empty_set, queue.list_scheduled
        assert_equal empty_set, queue.list_pending
        assert_equal empty_set, queue.list_dead
      end
    end

    it "but doesn't truncate the database" do
      clean_slate do
        backend.set key, field, "value"
        queue.flush
        assert_equal "value", backend.get key, field
      end
    end
  end
end
