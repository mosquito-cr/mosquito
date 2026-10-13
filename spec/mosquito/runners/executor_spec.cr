require "../../spec_helper"

describe "Mosquito::Runners::Executor" do
  getter(queue_list) { MockQueueList.new }
  getter(overseer) { MockOverseer.new }
  getter(executor) { MockExecutor.new overseer.as(Mosquito::Runners::Overseer) }
  getter(api) { Mosquito::Api::Executor.new executor.object_id.to_s }
  getter(coordinator) { Mosquito::Runners::Coordinator.new queue_list }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.discovered_queues << job_class.queue
  end

  def run_job(job_class : Mosquito::Job.class)
    register job_class
    job_class.reset_performance_counter!
    job_run = job_class.new.enqueue
    executor.work_unit = WorkUnit.of(job_run, from: job_class.queue)
    executor.execute
  end

  describe "status" do
    it "starts as starting" do
      assert_equal Runnable::State::Starting, executor.state
    end

    it "broadcasts a ping when transitioning to idle" do
      executor.state = Runnable::State::Idle

      select
      when overseer.finished_notifier.receive
        assert true
      when timeout(0.5.seconds)
        refute true, "Timed out waiting for idle notifier"
      end
    end

    it "goes idle in pre_run" do
      executor.pre_run
      assert_equal Runnable::State::Idle, executor.state
    end
  end

  describe "running jobs" do
    it "runs a job from a queue" do
      clean_slate do
        run_job QueuedTestJob
        assert_equal 1, QueuedTestJob.performances
      end
    end

    it "reschedules a job that failed" do
      clean_slate do
        register FailingJob
        now = Time.utc

        job = FailingJob.new
        job_run = job.build_job_run
        job_run.store
        FailingJob.queue.enqueue job_run

        Timecop.freeze now do
          executor.work_unit = WorkUnit.of(job_run, from: FailingJob.queue)
          executor.execute
        end

        job_run.reload
        assert_equal 1, job_run.retry_count

        Timecop.freeze now + job.reschedule_interval(1) do
          coordinator.enqueue_delayed_jobs
          executor.work_unit = WorkUnit.of(job_run, from: FailingJob.queue)
          executor.execute
        end

        job_run.reload
        assert_equal 2, job_run.retry_count
      end
    end

    it "reschedules a job whose type has no registered job class" do
      clean_slate do
        queue = Mosquito::Queue.new "unregistered_queue"
        job_run = Mosquito::JobRun.new "unregistered_job"
        job_run.store
        queue.enqueue job_run
        queue.dequeue

        executor.work_unit = WorkUnit.of(job_run, from: queue)
        executor.execute

        assert_equal 1, queue.backend.scheduled_size, "job was not rescheduled"
        assert_equal 0, queue.backend.dead_size
        assert_equal 1, Mosquito::JobRun.retrieve(job_run.id).try(&.retry_count)
      end
    end

    it "banishes a job which fails with retry: false instead of rescheduling it" do
      clean_slate do
        register NoRetryFailingJob
        queue = NoRetryFailingJob.queue

        job_run = NoRetryFailingJob.new.build_job_run
        job_run.store
        queue.enqueue job_run

        executor.work_unit = WorkUnit.of(job_run, from: queue)
        executor.execute

        assert_includes queue.backend.list_dead, job_run.id
        assert_equal 0, queue.backend.scheduled_size, "job was rescheduled despite retry: false"
      end
    end

    it "banishes a job whose before hook raises once it runs out of retries" do
      clean_slate do
        register BeforeHookFailingJob
        queue = BeforeHookFailingJob.queue

        job_run = BeforeHookFailingJob.new.build_job_run
        job_run.store
        queue.enqueue job_run

        # The retry limit is 5, so 10 attempts is plenty if retries are counted.
        attempts = 0
        10.times do
          attempts += 1
          attempt = Mosquito::JobRun.retrieve(job_run.id).not_nil!
          executor.work_unit = WorkUnit.of(attempt, from: queue)
          executor.execute
          break if queue.backend.list_dead.includes?(job_run.id)
        end

        retry_count = Mosquito::JobRun.retrieve(job_run.id).not_nil!.retry_count
        assert_includes queue.backend.list_dead, job_run.id,
          "job was never banished: still being rescheduled after #{attempts} attempts (retry_count=#{retry_count})"
      end
    end

    it "schedules deletion of a job_run it had to banish after a crash" do
      clean_slate do
        # The job can't be built, so it raises both when the job is run and
        # when the failure is handled.
        register UnbuildableJob
        queue = UnbuildableJob.queue
        job_run = Mosquito::JobRun.new "unbuildable_job"
        job_run.store
        queue.enqueue job_run
        queue.dequeue

        # Eagerly evaluate to avoid a race in lazy getter initialization
        # across fibers.
        pipeline = executor.job_pipeline
        done = Channel(Nil).new(1)

        spawn { pipeline.send WorkUnit.of(job_run, from: queue) }
        spawn do
          executor.each_run
          done.send nil
        end

        select
        when done.receive
        when timeout(2.seconds)
          refute true, "Timed out waiting for the executor to handle the job"
        end

        assert_includes queue.backend.list_dead, job_run.id
        assert_equal executor.failed_job_ttl, backend.expires_in(job_run.config_key)
      end
    end

    it "schedules deletion of a job_run that hard failed" do
      clean_slate do
        register NonReschedulableFailingJob

        job = NonReschedulableFailingJob.new
        job_run = job.build_job_run
        job_run.store
        NonReschedulableFailingJob.queue.enqueue job_run

        executor.work_unit = WorkUnit.of(job_run, from: NonReschedulableFailingJob.queue)
        executor.execute

        actual_ttl = backend.expires_in job_run.config_key
        assert_equal executor.failed_job_ttl, actual_ttl
      end
    end

    it "purges a successful job_run from the backend" do
      clean_slate do
        register QueuedTestJob

        job = QueuedTestJob.new
        job_run = job.build_job_run
        job_run.store
        QueuedTestJob.queue.enqueue job_run

        executor.work_unit = WorkUnit.of(job_run, from: QueuedTestJob.queue)
        executor.execute

        assert_logs_match "Success"

        QueuedTestJob.queue.enqueue job_run
        actual_ttl = Mosquito.backend.expires_in job_run.config_key
        assert_equal executor.successful_job_ttl, actual_ttl
      end
    end

    it "doesnt reschedule a job that cant be rescheduled" do
      clean_slate do
        run_job NonReschedulableFailingJob
        assert_logs_match "cannot be rescheduled"
      end
    end

    it "tells the observer what it's working on" do
      SleepyJob.should_sleep = true
      job = SleepyJob.new
      job_run = job.build_job_run
      job_run.store

      job_started = Channel(Bool).new
      job_finished = Channel(Bool).new

      # Eagerly evaluate to avoid race condition in lazy
      # getter initialization across fibers.
      executor
      api

      spawn {
        executor.work_unit = WorkUnit.of(job_run, from: SleepyJob.queue)
        executor.execute
        job_finished.send true
      }

      spawn {
        loop {
          break if api.current_job
        }
        assert_equal job_run.id, api.current_job
        assert_equal SleepyJob.queue.name, api.current_job_queue
        job_started.send true
      }

      select
      when job_started.receive
      when timeout(0.5.seconds)
        refute true, "Timed out waiting for job to start"
      end

      SleepyJob.should_sleep = false

      select
      when job_finished.receive
      when timeout(0.5.seconds)
        refute true, "Timed out waiting for job to finish"
      end

      assert_nil api.current_job, "Job should be cleared after finishing"
      assert_nil api.current_job_queue, "Queue should be cleared after finishing"
    end
  end

  describe "logs success/failures messages" do
    it "logs a success message when the job succeeds" do
      clean_slate do
        run_job QueuedTestJob
        assert_logs_match "Success"
      end
    end

    it "logs a failure message when the job fails" do
      clean_slate do
        run_job FailingJob
        assert_logs_match "Failure"
      end
    end
  end

  describe "job timing messages" do
    it "logs the time a job took to run" do
      clean_slate do
        run_job QueuedTestJob
        assert_logs_match "and took"
      end
    end

    it "logs the time a job took to run when the job fails" do
      clean_slate do
        run_job FailingJob
        assert_logs_match "taking"
      end
    end
  end

  describe "start and finish messages" do
    it "logs the job run start message" do
      clean_slate do
        run_job QueuedTestJob
        assert_logs_match "Starting: queued_test_job"
      end
    end
  end
end
