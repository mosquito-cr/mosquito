require "../spec_helper"

# Repro: when an orphaned periodic job run is recovered and banished via
# JobRun#retry_or_banish, finished_at is never set. The banished run is kept
# around for failed_job_ttl, and PeriodicJobRun#pending_job_run? treats it as
# still pending, skipping every interval until the config expires.
describe "orphaned periodic job run recovery" do
  getter interval : Time::Span = 2.minutes
  getter(overseer : MockOverseer) { MockOverseer.new }

  it "sets finished_at when retry_or_banish banishes a job run" do
    clean_slate do
      Mosquito::Base.register_job_mapping PeriodicTestJob.name.underscore, PeriodicTestJob

      job_run = PeriodicTestJob.new.build_job_run
      job_run.store
      PeriodicTestJob.queue.enqueue job_run
      PeriodicTestJob.queue.dequeue

      job_run.retry_or_banish PeriodicTestJob.queue

      assert_includes PeriodicTestJob.queue.backend.list_dead, job_run.id
      reloaded = Mosquito::JobRun.retrieve(job_run.id)
      refute_nil reloaded, "banished job run is retained for failed_job_ttl"
      refute_nil reloaded.not_nil!.finished_at, "banished job run has no finished_at"
    end
  end

  it "enqueues the next interval after an orphaned run is banished by the overseer" do
    clean_slate do
      Mosquito::Base.register_job_mapping PeriodicTestJob.name.underscore, PeriodicTestJob
      now = Time.utc.at_beginning_of_second
      periodic = Mosquito::PeriodicJobRun.new PeriodicTestJob, interval
      queue = PeriodicTestJob.queue

      # Scheduler enqueues the periodic job.
      Timecop.freeze(now) do
        periodic.last_executed_at = now - interval
        assert periodic.try_to_execute
      end
      pending_id = periodic.metadata["pending_run_id"]?.not_nil!

      # A worker picks it up and is killed mid-run (e.g. during a deploy).
      dead_overseer = MockOverseer.new
      assert_equal pending_id, queue.dequeue.not_nil!.id
      Mosquito::JobRun.retrieve(pending_id).not_nil!.claimed_by dead_overseer

      # A live overseer recovers the orphan. Periodic jobs are never
      # rescheduleable, so it is banished.
      Mosquito.backend.register_overseer overseer.observer.instance_id
      overseer.cleanup_orphaned_pending_jobs
      assert_includes queue.backend.list_dead, pending_id

      # Next interval: the scheduler should enqueue a fresh run.
      waiting_before = queue.backend.list_waiting.size
      Timecop.freeze(now + interval) do
        periodic.try_to_execute
      end

      assert_equal waiting_before + 1, queue.backend.list_waiting.size,
        "periodic job was skipped: banished run #{pending_id} still looks pending"
    end
  end
end
