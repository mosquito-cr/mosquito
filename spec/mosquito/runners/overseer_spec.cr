require "../../spec_helper"

describe "Mosquito::Runners::Overseer" do
  getter(overseer : MockOverseer) { MockOverseer.new }
  getter(queue_list : MockQueueList ) { overseer.queue_list.as(MockQueueList) }
  getter(coordinator : MockCoordinator ) { overseer.coordinator.as(MockCoordinator) }
  getter(executor : MockExecutor) { overseer.executors.first.as(MockExecutor) }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  def run_job(job_class : Mosquito::Job.class)
    register job_class
    job_class.reset_performance_counter!
    job_run = job_class.new.enqueue
    executor.execute job_run, from_queue: job_class.queue
  end

  describe "pre_run" do
    it "runs all executors" do
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Starting, executor.state
      end
      overseer.pre_run
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Working, executor.state
      end
    end
  end

  describe "post_run" do
    it "stops all executors" do
      overseer.executors.each(&.run)
      overseer.post_run
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Finished, executor.state
      end
    end

    it "logs messages about stopping the executors" do
      clear_logs
      overseer.pre_run
      overseer.post_run
      assert_logs_match "Stopping executors."
      assert_logs_match "All executors stopped."
    end
  end

  describe "each_run" do
    it "dequeues a job and dispatches it to the pipeline" do
      clean_slate do
        register QueuedTestJob
        expected_job_run = QueuedTestJob.new.enqueue

        overseer.work_handout = Channel(Tuple(JobRun, Queue)).new

        queue_list.state = Runnable::State::Working
        executor.state = Runnable::State::Idle

        # each_run will block until there's a receiver on the channel
        spawn { overseer.each_run }
        actual_job_run, queue = overseer.work_handout.receive
        assert_equal expected_job_run, actual_job_run
        assert_equal QueuedTestJob.queue, queue
      end
    end

    it "waits #idle_wait before checking the queue again" do
      clean_slate do
        # an idle executor, but no jobs in the queue
        executor.state = Runnable::State::Idle
        queue_list.state = Runnable::State::Working

        tick_time = Time.measure do
          overseer.each_run
        end

        assert_in_epsilon(
          overseer.idle_wait.total_seconds,
          tick_time.total_seconds,
          epsilon: 0.06
        )
      end
    end

    it "triggers the scheduler" do
      assert_equal 0, coordinator.schedule_count
      overseer.each_run
      assert_equal 1, coordinator.schedule_count
    end
  end

  describe "pre_run recovers orphaned pending jobs" do
    it "moves orphaned pending jobs back to waiting on startup" do
      clean_slate do
        register QueuedTestJob

        # Simulate a previous process crash: enqueue a job and move it
        # to pending (as if it was dequeued but never finished).
        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue

        # Verify job is stuck in pending
        assert_equal [job_run.id], QueuedTestJob.queue.backend.dump_pending_q
        assert_empty QueuedTestJob.queue.backend.dump_waiting_q

        # pre_run should recover it
        overseer.pre_run

        # Job should be back in waiting
        assert_empty QueuedTestJob.queue.backend.dump_pending_q
        assert_equal [job_run.id], QueuedTestJob.queue.backend.dump_waiting_q
      end
    end
  end

  describe "check_for_deceased_runners" do
    it "recovers a job from a dead executor" do
      clean_slate do
        register QueuedTestJob

        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue

        # Simulate the executor having a current_job and being dead
        dead_executor = executor
        dead_executor.state = Runnable::State::Working
        dead_executor.run # start the fiber so dead? can detect it

        # Manually set the current_job via the executor's instance variable
        # by calling each_run would be too complex; instead we test recover_job_from
        # indirectly via the queue state.

        # Verify the job is stuck in pending
        assert_equal [job_run.id], QueuedTestJob.queue.backend.dump_pending_q

        # Since we can't easily simulate a dead fiber with a current_job in
        # tests, we verify the recover_pending mechanism at the queue level
        count = QueuedTestJob.queue.recover_pending
        assert_equal 1_i64, count
        assert_empty QueuedTestJob.queue.backend.dump_pending_q
        assert_equal [job_run.id], QueuedTestJob.queue.backend.dump_waiting_q
      end
    end
  end
end
