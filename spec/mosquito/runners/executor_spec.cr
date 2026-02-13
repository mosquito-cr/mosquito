require "../../spec_helper"

describe "Mosquito::Runners::Executor" do
  getter(queue_list) { MockQueueList.new }
  getter(overseer) { MockOverseer.new }
  getter(executor) { MockExecutor.new overseer.as(Mosquito::Runners::Overseer) }
  getter(api) { Mosquito::Api::Executor.new executor.object_id.to_s }
  getter(coordinator) { Mosquito::Runners::Coordinator.new queue_list }

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

  describe "status" do
    it "starts as starting" do
      assert_equal Runnable::State::Starting, executor.state
    end

    it "broadcasts a ping when transitioning to idle" do
      executor.state = Runnable::State::Idle

      select
      when overseer.idle_notifier.receive
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
          executor.execute job_run, from_queue: job.class.queue
        end

        job_run.reload
        assert_equal 1, job_run.retry_count

        Timecop.freeze now + job.reschedule_interval(1) do
          coordinator.enqueue_delayed_jobs
          executor.execute job_run, from_queue: job.class.queue
        end

        job_run.reload
        assert_equal 2, job_run.retry_count
      end
    end

    it "schedules deletion of a job_run that hard failed" do
      clean_slate do
        register NonReschedulableFailingJob

        job = NonReschedulableFailingJob.new
        job_run = job.build_job_run
        job_run.store
        NonReschedulableFailingJob.queue.enqueue job_run

        executor.execute job_run, from_queue: NonReschedulableFailingJob.queue

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

        executor.execute job_run, from_queue: QueuedTestJob.queue

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

      spawn {
        executor.execute job_run, from_queue: SleepyJob.queue
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
