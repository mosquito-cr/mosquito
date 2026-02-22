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

  describe "dequeue_job? stamps overseer_id" do
    it "claims the job run with the overseer's instance id on dequeue" do
      clean_slate do
        register QueuedTestJob
        job_run = QueuedTestJob.new.enqueue

        queue_list.state = Runnable::State::Working

        result = overseer.dequeue_job?
        assert result
        dequeued_job_run, _queue = result.not_nil!

        assert_equal overseer.observer.instance_id, dequeued_job_run.overseer_id
      end
    end
  end

  describe "cleanup_orphaned_pending_jobs" do
    it "recovers a pending job whose overseer is dead" do
      clean_slate do
        register QueuedTestJob

        # Use a separate overseer that won't be registered as alive.
        dead_overseer = MockOverseer.new

        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue
        job_run.claimed_by dead_overseer

        # Verify job is stuck in pending
        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id
        assert_equal 0, job_run.retry_count

        # Register only the *live* overseer
        Mosquito.backend.register_overseer overseer.observer.instance_id

        # Run cleanup — dead_overseer's id won't be in the active set
        overseer.cleanup_orphaned_pending_jobs

        # Job should be removed from pending and rescheduled
        assert_empty QueuedTestJob.queue.backend.dump_pending_q
        assert_includes QueuedTestJob.queue.backend.dump_scheduled_q, job_run.id

        # Retry count should be incremented
        job_run.reload
        assert_equal 1, job_run.retry_count
      end
    end

    it "does not touch pending jobs from a live overseer" do
      clean_slate do
        register QueuedTestJob

        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue

        # Claim with the live overseer
        Mosquito.backend.register_overseer overseer.observer.instance_id
        job_run.claimed_by overseer

        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id

        overseer.cleanup_orphaned_pending_jobs

        # Job should still be in pending — its overseer is alive
        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id
      end
    end

    it "claims unclaimed pending jobs without recovering them" do
      clean_slate do
        register QueuedTestJob

        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue

        # No claim — simulates a job from before this feature
        assert_nil job_run.overseer_id
        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id

        Mosquito.backend.register_overseer overseer.observer.instance_id
        overseer.cleanup_orphaned_pending_jobs

        # Job should still be in pending (not recovered)
        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id

        # But it should now be claimed by this overseer
        job_run.reload
        assert_equal overseer.observer.instance_id, job_run.overseer_id
      end
    end

    it "banishes an orphaned job that has exhausted retries" do
      clean_slate do
        register QueuedTestJob

        dead_overseer = MockOverseer.new

        # Create a job_run with retry_count=4 so the next failure (count=5)
        # exceeds the default rescheduleable? limit of < 5.
        job_run = Mosquito::JobRun.new("queued_test_job", retry_count: 4)
        job_run.store

        QueuedTestJob.queue.enqueue job_run
        QueuedTestJob.queue.dequeue
        job_run.claimed_by dead_overseer

        assert_includes QueuedTestJob.queue.backend.dump_pending_q, job_run.id

        Mosquito.backend.register_overseer overseer.observer.instance_id
        overseer.cleanup_orphaned_pending_jobs

        # Job should be removed from pending and moved to dead
        assert_empty QueuedTestJob.queue.backend.dump_pending_q
        assert_empty QueuedTestJob.queue.backend.dump_waiting_q
        assert_empty QueuedTestJob.queue.backend.dump_scheduled_q
        assert_includes QueuedTestJob.queue.backend.dump_dead_q, job_run.id
      end
    end
  end
end
