require "../spec_helper"

describe "Job#next_batch hook" do
  getter(queue_list) { MockQueueList.new }
  getter(overseer) { MockOverseer.new }
  getter(executor) { MockExecutor.new overseer.as(Mosquito::Runners::Overseer) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.discovered_queues << job_class.queue
  end

  # Build and execute a job without adding the trigger to the queue,
  # so that queue.size afterward reflects only the next_batch items.
  def run_perpetual_job(value = "trigger")
    register PerpetualTestJob
    PerpetualTestJob.reset_performance_counter!
    job = PerpetualTestJob.new(value: value)
    job_run = job.build_job_run
    job_run.store
    executor.work_unit = Mosquito::WorkUnit.of(job_run, from: PerpetualTestJob.queue)
    executor.execute
  end

  it "returns an empty array by default" do
    job = JobWithPerformanceCounter.new
    assert_equal [] of Mosquito::Job, job.next_batch
  end

  it "enqueues next_batch jobs after a successful run" do
    clean_slate do
      PerpetualTestJob.next_batch_items = [
        PerpetualTestJob.new(value: "followup").as(Mosquito::Job),
      ]

      run_perpetual_job

      assert_equal 1, PerpetualTestJob.performances
      queue_size = PerpetualTestJob.queue.size(include_dead: false)
      assert_equal 1, queue_size
    end
  ensure
    PerpetualTestJob.next_batch_items = [] of Mosquito::Job
  end

  it "does not enqueue next_batch jobs after a failed run" do
    clean_slate do
      register FailingJob

      job = FailingJob.new
      job_run = job.build_job_run
      job_run.store
      executor.work_unit = Mosquito::WorkUnit.of(job_run, from: FailingJob.queue)
      executor.execute

      # FailingJob has no next_batch override — nothing extra enqueued
      queue_size = PerpetualTestJob.queue.size(include_dead: false)
      assert_equal 0, queue_size
    end
  end

  it "enqueues multiple jobs from next_batch" do
    clean_slate do
      PerpetualTestJob.next_batch_items = [
        PerpetualTestJob.new(value: "one").as(Mosquito::Job),
        PerpetualTestJob.new(value: "two").as(Mosquito::Job),
        PerpetualTestJob.new(value: "three").as(Mosquito::Job),
      ]

      run_perpetual_job

      queue_size = PerpetualTestJob.queue.size(include_dead: false)
      assert_equal 3, queue_size
    end
  ensure
    PerpetualTestJob.next_batch_items = [] of Mosquito::Job
  end

  it "does nothing when next_batch returns empty" do
    clean_slate do
      PerpetualTestJob.next_batch_items = [] of Mosquito::Job

      run_perpetual_job

      queue_size = PerpetualTestJob.queue.size(include_dead: false)
      assert_equal 0, queue_size
    end
  end
end
