require "../../test_helper"

describe "Mosquito::Runners::Coordinator" do
  getter(queue : Queue) { test_job.class.queue }
  getter(test_job) { QueuedTestJob.new }
  getter(queue_list) { MockQueueList.new }
  getter(coordinator) { MockCoordinator.new queue_list }
  getter(enqueue_time) { Time.utc }

  def enqueue_job_run : JobRun
    queue_list.queues << queue

    job_run = JobRun.new "blah"

    Timecop.freeze enqueue_time do |t|
      job_run = test_job.enqueue in: 3.seconds
    end

    assert_includes queue.backend.dump_scheduled_q, job_run.id
    job_run
  end

  def opt_in_to_locking
    Mosquito.temp_config(run_cron_scheduler: false, use_distributed_lock: true) do
      yield
    end
  end

  describe "only_if_coordinator" do
    getter(coordinator1) { Mosquito::Runners::Coordinator.new queue_list }
    getter(coordinator2) { Mosquito::Runners::Coordinator.new queue_list }

    it "runs when use_cron_scheduler is true" do
      Mosquito.temp_config(run_cron_scheduler: true, use_distributed_lock: false) do
        coordinator_ran = true
        coordinator1.only_if_coordinator do
          coordinator_ran = false
        end
      end
    end

    it "gets a lock from the backend" do
      opt_in_to_locking do
        gotten = false

        coordinator1.only_if_coordinator do
          gotten = true
        end

        assert gotten
      end
    end

    it "fails to get a lock from the backend" do
      opt_in_to_locking do
        gotten = false

        coordinator1.only_if_coordinator do
          coordinator2.only_if_coordinator do
            gotten = true
          end
        end

        refute gotten
      end
    end

    it "releases the lock from the backend" do
      opt_in_to_locking do
        gotten = false

        coordinator1.only_if_coordinator do
        end

        coordinator2.only_if_coordinator do
          gotten = true
        end

        assert gotten
      end
    end

    it "sets a ttl on the lock" do
      opt_in_to_locking do
        coordinator1.only_if_coordinator do
          assert Mosquito.backend.expires_in(coordinator.lock_key) > 0
        end
      end
    end

    it "warns when coordination takes too long" do
      opt_in_to_locking do
        clear_logs

        Timecop.scale 100 do
          # 1 actual second is measured as 100 seconds

          coordinator1.only_if_coordinator do
            sleep 0.1 # scaled to 10s by Timecop
          end
        end

        assert_logs_match "took longer than LockTTL"
      end
    end
  end

  describe "enqueue_periodic_jobs" do
    it "enqueues a scheduled job_run at the appropriate time" do
      clean_slate do
        queue = PeriodicTestJob.queue
        Mosquito::Base.register_job_mapping PeriodicTestJob.name, PeriodicTestJob
        Mosquito::Base.register_job_interval PeriodicTestJob, interval: 1.second

        Timecop.freeze(enqueue_time) do
          coordinator.enqueue_periodic_jobs
        end

        queued_job_runs = queue.backend.dump_waiting_q
        assert queued_job_runs.size >= 1

        last_job_run = queued_job_runs.last
        job_run_metadata = queue.backend.retrieve JobRun.config_key(last_job_run)

        assert_equal enqueue_time.to_unix_ms.to_s, job_run_metadata["enqueue_time"]
      end
    end
  end

  describe "enqueue_delayed_jobs" do
    it "enqueues a delayed job_run when it's ready" do
      clean_slate do
        job_run = enqueue_job_run
        run_time = enqueue_time + 3.seconds

        Timecop.freeze run_time do |t|
          coordinator.enqueue_delayed_jobs
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
          coordinator.enqueue_delayed_jobs
        end

        queued_job_runs = queue.backend.dump_waiting_q

        # does not deschedule and enqueue anything
        assert_equal 0, queued_job_runs.size
      end
    end

    it "logs when it finds delayed job_runs" do
      clean_slate do
        clear_logs
        enqueue_job_run
        Timecop.freeze enqueue_time + 3.seconds do |t|
          coordinator.enqueue_delayed_jobs
        end
        assert_logs_match "1 delayed jobs ready"
      end
    end

  end
end
