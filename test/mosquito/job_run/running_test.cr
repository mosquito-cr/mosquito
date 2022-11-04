require "../../test_helper"

describe "job_run running" do
  it "uses the lookup table to build a job" do
    job_instance = create_job_run.build_job
    assert_equal JobWithConfig, job_instance.class
  end

  it "populates the variables of a job" do
    job_instance = create_job_run.build_job

    unless job_instance.is_a? JobWithConfig
      raise "Expected to get a JobWithConfig back, but got a #{job_instance.class}"
    end

    assert_equal job_run_config, job_instance.config
  end

  it "runs the job" do
    JobWithPerformanceCounter.reset_performance_counter!
    create_job_run("job_with_performance_counter").run
    assert_equal 1, JobWithPerformanceCounter.performances
  end
end
