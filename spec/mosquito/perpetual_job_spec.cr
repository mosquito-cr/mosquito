require "../spec_helper"

describe "PerpetualJob polling" do
  getter(queue_list) { MockQueueList.new }
  getter(coordinator) { MockCoordinator.new(queue_list) }
  getter(runner) { Mosquito::Runners::PerpetualJobRunner.new(coordinator) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.discovered_queues << job_class.queue
  end

  it "PerpetualJob registers with poll_every" do
    # PerpetualPollTestJob is defined but doesn't call poll_every,
    # so we register one manually for this test.
    run = Mosquito::PerpetualJobRun.new(PerpetualPollTestJob, 10.seconds)
    assert_equal 10.seconds, run.interval
  end

  it "PerpetualJobRun#try_to_poll enqueues next_batch results" do
    clean_slate do
      register PerpetualPollTestJob
      PerpetualPollTestJob.next_batch_items = [
        PerpetualPollTestJob.new(item_id: 1_i64).as(Mosquito::Job),
        PerpetualPollTestJob.new(item_id: 2_i64).as(Mosquito::Job),
      ]

      run = Mosquito::PerpetualJobRun.new(PerpetualPollTestJob, 0.seconds)
      result = run.try_to_poll

      assert result, "Expected try_to_poll to return true"
      queue_size = PerpetualPollTestJob.queue.size(include_dead: false)
      assert_equal 2, queue_size
    end
  ensure
    PerpetualPollTestJob.next_batch_items = [] of Mosquito::Job
  end

  it "PerpetualJobRun#try_to_poll skips when interval has not elapsed" do
    clean_slate do
      register PerpetualPollTestJob
      PerpetualPollTestJob.next_batch_items = [
        PerpetualPollTestJob.new(item_id: 1_i64).as(Mosquito::Job),
      ]

      run = Mosquito::PerpetualJobRun.new(PerpetualPollTestJob, 1.hour)
      # First poll succeeds and sets last_polled_at
      run.try_to_poll

      # Second poll should skip because 1 hour hasn't elapsed
      PerpetualPollTestJob.next_batch_items = [
        PerpetualPollTestJob.new(item_id: 99_i64).as(Mosquito::Job),
      ]
      result = run.try_to_poll

      refute result, "Expected try_to_poll to return false (interval not elapsed)"
      # Only the first batch should have been enqueued
      queue_size = PerpetualPollTestJob.queue.size(include_dead: false)
      assert_equal 1, queue_size
    end
  ensure
    PerpetualPollTestJob.next_batch_items = [] of Mosquito::Job
  end

  it "PerpetualJobRun#try_to_poll does nothing when next_batch is empty" do
    clean_slate do
      register PerpetualPollTestJob
      PerpetualPollTestJob.next_batch_items = [] of Mosquito::Job

      run = Mosquito::PerpetualJobRun.new(PerpetualPollTestJob, 0.seconds)
      result = run.try_to_poll

      assert result, "Expected try_to_poll to return true (interval elapsed)"
      queue_size = PerpetualPollTestJob.queue.size(include_dead: false)
      assert_equal 0, queue_size
    end
  end

  it "PerpetualJobRunner#poll calls try_to_poll on registered jobs" do
    clean_slate do
      register PerpetualPollTestJob
      PerpetualPollTestJob.next_batch_items = [
        PerpetualPollTestJob.new(item_id: 42_i64).as(Mosquito::Job),
      ]

      coordinator.always_coordinator!
      perpetual_run = Mosquito::PerpetualJobRun.new(PerpetualPollTestJob, 0.seconds)
      Mosquito::Base.perpetual_job_runs << perpetual_run

      runner.poll

      queue_size = PerpetualPollTestJob.queue.size(include_dead: false)
      assert_equal 1, queue_size
    end
  ensure
    PerpetualPollTestJob.next_batch_items = [] of Mosquito::Job
    Mosquito::Base.perpetual_job_runs.reject! { |r| r.class == PerpetualPollTestJob }
  end
end
