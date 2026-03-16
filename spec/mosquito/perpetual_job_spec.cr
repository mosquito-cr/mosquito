require "../spec_helper"

describe Mosquito::PerpetualJob do
  it "correctly renders job_name" do
    assert_equal "perpetual_test_job", PerpetualTestJob.job_name
  end

  it "builds a job_run with params" do
    job = PerpetualTestJob.new(value: "hello")
    job_run = job.build_job_run

    assert_instance_of JobRun, job_run
    assert_equal PerpetualTestJob.job_name, job_run.type
    assert_equal "hello", job_run.config["value"]
  end

  it "is not reschedulable" do
    refute PerpetualTestJob.new.rescheduleable?
  end

  it "registers in job mapping" do
    assert_equal PerpetualTestJob, Base.job_for_type(PerpetualTestJob.job_name)
  end

  it "schedules itself for an interval" do
    clean_slate do
      PerpetualTestJob.run_every 3.minutes
      perpetual_run = Base.perpetual_job_runs.first
      assert_equal PerpetualTestJob, perpetual_run.class
      assert_equal 3.minutes, perpetual_run.interval
    end
  end
end
