require "../../test_helper"

describe "Mosquito::Runner#enqueue_delayed_job_runs" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job)      { QueuedTestJob.new }
  getter(runner)        { Mosquito::TestableRunner.new }
  getter(enqueue_time)  { Time.utc }
  getter(backend)       { queue.backend }

  def enqueue_job_run : JobRun
    Mosquito::Base.register_job_mapping queue.name, QueuedTestJob

    job_run = JobRun.new "blah"

    Timecop.freeze enqueue_time do |t|
      job_run = test_job.enqueue in: 3.seconds
    end

    assert_includes queue.backend.dump_scheduled_q, job_run.id
    runner.run :fetch_queues
    job_run
  end

  it "enqueues a delayed job_run when it's ready" do
    clean_slate do
      job_run = enqueue_job_run
      run_time = enqueue_time + 3.seconds

      Timecop.freeze run_time do |t|
        runner.run :enqueue
      end

      queued_job_runs = queue.backend.dump_waiting_q
      assert_includes queued_job_runs, job_run.id

      last_job_run = queued_job_runs.last
      job_run_metadata = queue.backend.retrieve JobRun.config_key(last_job_run)

      assert_equal queue.name, job_run_metadata["type"]?
    end
  end

  it "doesn't enqueue job_runs that arent ready yet" do
    clean_slate do
      job_run = enqueue_job_run

      check_time = enqueue_time + 2.999.seconds

      Timecop.freeze check_time do |t|
        runner.run :enqueue
      end

      queued_job_runs = queue.backend.dump_waiting_q

      # does not deschedule and enqueue anything
      assert_equal 0, queued_job_runs.size
    end
  end
end
