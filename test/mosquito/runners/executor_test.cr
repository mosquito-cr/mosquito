require "../../test_helper"

describe "Mosquito::Runners::Executor" do
  getter(queue_list) { MockQueueList.new }
  getter(executor) { Mosquito::Runners::Executor.new queue_list }
  getter(coordinator) { Mosquito::Runners::Coordinator.new queue_list }

  describe "dequeue_and_run_jobs" do
  end

  describe "running jobs" do
    def register(job_class : Mosquito::Job.class)
      Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
      queue_list.queues << job_class.queue
    end

    def run_job(job_class : Mosquito::Job.class)
      register job_class
      job_class.reset_performance_counter!
      job_class.new.enqueue
      executor.run_next_job job_class.queue
    end

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
          executor.run_next_job job.class.queue
        end

        job_run.reload
        assert_equal 1, job_run.retry_count

        Timecop.freeze now + job.reschedule_interval(1) do
          coordinator.enqueue_delayed_jobs
          executor.run_next_job job.class.queue
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

        executor.run_next_job NonReschedulableFailingJob.queue

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

        executor.run_next_job QueuedTestJob.queue

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
  end
end
