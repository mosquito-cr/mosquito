require "../../test_helper"

describe "Mosquito::Runners::QueueList" do
  getter(queue_list) { MockQueueList.new }

  def enqueue_jobs
    PassingJob.new.enqueue
    FailingJob.new.enqueue
    EchoJob.new(text: "hello world").enqueue
  end

  describe "fetch" do
    it "returns a list of queues" do
      clean_slate do
        enqueue_jobs
        queue_list.fetch
        assert_equal ["failing_job", "io_queue", "passing_job"], queue_list.queues.map(&.name).sort
      end
    end

    it "logs a message about the number of fetched queues" do
      clean_slate do
        enqueue_jobs
        queue_list.fetch
        assert_logs_match "found 3 queues"
      end
    end
  end

  describe "queue filtering" do
    it "filters the list of queues when a whitelist is present" do
      clean_slate do
        enqueue_jobs

        Mosquito.temp_config(run_from: ["io_queue", "passing_job"]) do
          queue_list.fetch
        end
      end

      assert_equal ["io_queue", "passing_job"], queue_list.queues.map(&.name).sort
    end

    it "logs an error when all queues are filtered out" do
      clean_slate do
        enqueue_jobs

        Mosquito.temp_config(run_from: ["test4"]) do
          queue_list.fetch
        end

        assert_logs_match "No watchable queues found."
      end
    end

    it "doesnt log an error when no queues are present" do
      clean_slate do
        queue_list.fetch
        refute_logs_match "No watchable queues found."
      end
    end
  end
end
