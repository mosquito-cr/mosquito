require "../../spec_helper"

describe "Mosquito::Runners::QueueList" do
  getter(queue_list) { MockQueueList.new }

  def enqueue_jobs
    PassingJob.new.enqueue
    FailingJob.new.enqueue
    EchoJob.new(text: "hello world").enqueue
  end

  describe "each_run" do
    it "returns a list of queues" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run
        assert_equal ["failing_job", "io_queue", "passing_job"], queue_list.queues.map(&.name).sort
      end
    end

    it "logs a message about the number of fetched queues" do
      clean_slate do
        clear_logs
        enqueue_jobs
        queue_list.each_run
        assert_logs_match "found 3 new queues"
      end
    end
  end

  describe "queue filtering" do
    it "filters the list of queues when a whitelist is present" do
      clean_slate do
        enqueue_jobs

        Mosquito.temp_config(run_from: ["io_queue", "passing_job"]) do
          queue_list.each_run
        end
      end

      assert_equal ["io_queue", "passing_job"], queue_list.queues.map(&.name).sort
    end

    it "logs an error when all queues are filtered out" do
      clean_slate do
        enqueue_jobs

        Mosquito.temp_config(run_from: ["test4"]) do
          queue_list.each_run
        end

        assert_logs_match "No watchable queues found."
      end
    end

    it "doesnt log an error when no queues are present" do
      clean_slate do
        queue_list.each_run
        refute_logs_match "No watchable queues found."
      end
    end
  end

  describe "paused queue filtering" do
    it "excludes paused queues from the queue list" do
      clean_slate do
        enqueue_jobs
        Mosquito::Queue.new("passing_job").pause
        queue_list.each_run
        assert_equal ["failing_job", "io_queue"], queue_list.queues.map(&.name).sort
      end
    end

    it "logs a message about paused queues" do
      clean_slate do
        clear_logs
        enqueue_jobs
        Mosquito::Queue.new("passing_job").pause
        queue_list.each_run
        assert_logs_match "1 paused queues: passing_job"
      end
    end

    it "includes queues again after they are resumed" do
      clean_slate do
        enqueue_jobs
        q = Mosquito::Queue.new("passing_job")
        q.pause
        queue_list.each_run
        refute_includes queue_list.queues.map(&.name), "passing_job"

        q.resume
        queue_list.each_run
        assert_includes queue_list.queues.map(&.name), "passing_job"
      end
    end
  end

  describe "resource gate filtering" do
    it "excludes queues whose gate blocks" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 90.0 }
        queue_list.resource_gates = {"passing_job" => gate.as(Mosquito::ResourceGate)}

        refute_includes queue_list.queues.map(&.name), "passing_job"
        assert_includes queue_list.queues.map(&.name), "failing_job"
        assert_includes queue_list.queues.map(&.name), "io_queue"
      end
    end

    it "includes queues whose gate allows" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 50.0 }
        queue_list.resource_gates = {"passing_job" => gate.as(Mosquito::ResourceGate)}

        assert_includes queue_list.queues.map(&.name), "passing_job"
      end
    end

    it "ungated queues are always included" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 90.0 }
        queue_list.resource_gates = {"passing_job" => gate.as(Mosquito::ResourceGate)}

        assert_equal 2, queue_list.queues.size
      end
    end

    it "multiple queues can share a gate" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 90.0 }
        queue_list.resource_gates = {
          "passing_job" => gate.as(Mosquito::ResourceGate),
          "failing_job" => gate.as(Mosquito::ResourceGate),
        }

        assert_equal ["io_queue"], queue_list.queues.map(&.name)
      end
    end

    it "gate state is evaluated on each access" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        value = 90.0
        gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { value }
        queue_list.resource_gates = {"passing_job" => gate.as(Mosquito::ResourceGate)}

        refute_includes queue_list.queues.map(&.name), "passing_job"

        value = 50.0
        assert_includes queue_list.queues.map(&.name), "passing_job"
      end
    end

    it "returns all queues when no gates are configured" do
      clean_slate do
        enqueue_jobs
        queue_list.each_run

        assert_equal 3, queue_list.queues.size
      end
    end
  end
end
