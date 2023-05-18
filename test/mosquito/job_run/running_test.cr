require "../../test_helper"

describe "job_run running" do
  it "uses the lookup table to build a job" do
    job_instance = create_job_run.build_job
    assert_instance_of JobWithConfig, job_instance
  end

  it "populates the variables of a job" do
    job_instance = create_job_run.build_job

    assert_instance_of JobWithConfig, job_instance
    assert_equal job_run_config, job_instance.as(JobWithConfig).config
  end

  it "runs the job" do
    JobWithPerformanceCounter.reset_performance_counter!
    create_job_run("job_with_performance_counter").run
    assert_equal 1, JobWithPerformanceCounter.performances
  end
end
