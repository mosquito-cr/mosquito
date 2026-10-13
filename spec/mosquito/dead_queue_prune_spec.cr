require "../spec_helper"

describe "dead queue pruning" do
  it "removes banished job ids once their config has expired" do
    clean_slate do
      Mosquito::Base.register_job_mapping PeriodicTestJob.name.underscore, PeriodicTestJob
      queue = PeriodicTestJob.queue

      job_run = PeriodicTestJob.new.build_job_run
      job_run.store
      queue.enqueue job_run
      queue.dequeue
      job_run.retry_or_banish queue

      assert_equal 0, queue.prune_dead, "live dead job run should be kept"
      assert_includes queue.backend.list_dead, job_run.id

      job_run.delete
      assert_equal 1, queue.prune_dead
      refute_includes queue.backend.list_dead, job_run.id
    end
  end

  it "prunes at most the given limit per call" do
    clean_slate do
      Mosquito::Base.register_job_mapping PeriodicTestJob.name.underscore, PeriodicTestJob
      queue = PeriodicTestJob.queue

      3.times do
        job_run = PeriodicTestJob.new.build_job_run
        job_run.store
        queue.enqueue job_run
        queue.dequeue
        job_run.retry_or_banish queue
        job_run.delete
      end

      assert_equal 2, queue.prune_dead(limit: 2)
      assert_equal 1, queue.prune_dead(limit: 2)
      assert_equal 0, queue.backend.list_dead.size
    end
  end
end
