require "../../spec_helper"

describe Mosquito::Api::Queue do
  let(job_classes) {
    [QueuedTestJob, PassingJob, FailingJob, QueueHookedTestJob]
  }
  let(queued_test_job) { QueuedTestJob.new }
  let(passing_job) { PassingJob.new }

  it "can fetch a list of current queues" do
    clean_slate do
      queued_test_job.enqueue
      passing_job.enqueue
      expected_queues = ["queued_test_job", "passing_job"].sort
      queues = Mosquito::Api::Queue.all
      assert_equal 2, queues.size
      assert_equal expected_queues, queues.map(&.name).sort
    end
  end

  it "can fetch the size of a queue" do
    clean_slate do
      job_classes.map(&.new).each(&.enqueue)
      queues = Mosquito::Api::Queue.all
      queues.each do |queue|
        assert_equal 1, queue.size
      end
    end
  end

  it "can fetch the size details of a queue" do
    clean_slate do
      job_classes.map(&.new).each(&.enqueue)
      queues = Mosquito::Api::Queue.all
      sizes = queues.map(&.size_details)
      sizes.each do |size|
        assert_equal 1, size["waiting"]
        assert_equal 0, size["scheduled"]
        assert_equal 0, size["pending"]
        assert_equal 0, size["dead"]
      end
    end
  end

  it "can fetch job runs from a queue" do
    clean_slate do
      job_classes.each do |job_class|
        job = job_class.new
        job.enqueue
        api = Mosquito::Api::Queue.new job_class.queue.name
        job_runs = api.waiting_job_runs
        assert_equal 1, job_runs.size
        assert_equal job.class.name.underscore, job_runs.first.type
      end
    end
  end

  it "publishes an event when a job is enqueued" do
    eavesdrop do
      queued_test_job.enqueue
    end
    assert_message_received /enqueued/
  end

  it "publishes an event when a job is enqueued for later" do
    eavesdrop do
      queued_test_job.enqueue(60.seconds.from_now)
    end
    assert_message_received /enqueued/
  end

  it "publishes an event when a job is dequeued" do
    clean_slate do
      queued_test_job.enqueue

      eavesdrop do
        queued_test_job.class.queue.dequeue
      end
    end

    assert_message_received /dequeued/
  end
end
