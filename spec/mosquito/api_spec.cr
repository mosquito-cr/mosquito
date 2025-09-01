require "../spec_helper"

describe Mosquito::Api do
  let(queued_test_job) { QueuedTestJob.new }
  let(passing_job) { PassingJob.new }

  it "can fetch a list of queues" do
    clean_slate do
      queued_test_job.enqueue
      passing_job.enqueue
      queues = Mosquito::Api.list_queues
      assert_equal 2, queues.size
      queue_names = queues.map(&.name)
      assert_includes queue_names, queued_test_job.class.queue.name
      assert_includes queue_names, passing_job.class.queue.name
    end
  end
end
