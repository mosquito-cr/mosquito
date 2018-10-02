require "../../test_helper"

describe "Mosquito::Runner#run_next_task" do
  let(:runner) { Mosquito::TestableRunner.new }

  def register_mappings
    Mosquito::Base.register_job_mapping "mosquito::test_jobs::queued", Mosquito::TestJobs::Queued
    Mosquito::Base.register_job_mapping "failing_job", FailingJob
  end

  def run_task(job)
    job.reset_performance_counter!
    job.new.enqueue

    runner.run :fetch_queues
    runner.run :run
  end

  it "runs a task" do
    vanilla do
      register_mappings

      run_task Mosquito::TestJobs::Queued
      assert_equal 1, Mosquito::TestJobs::Queued.performances
    end
  end

  it "logs a success message" do
    vanilla do
      register_mappings

      clear_logs
      run_task Mosquito::TestJobs::Queued
      assert_includes logs, "Success"
    end
  end

  it "logs a failure message" do
    vanilla do
      register_mappings
      clear_logs
      run_task FailingJob
      assert_includes logs, "Failure"
    end
  end

  it "reschedules a job that failed" do
    skip
  end

  it "doesnt reschedule a job that cant be rescheduled" do
    skip
  end

  it "wont execute more than it should" do
    skip
  end
end
