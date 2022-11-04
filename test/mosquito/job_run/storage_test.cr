require "../../test_helper"

describe "job_run storage" do
  getter backend : Mosquito::Backend = Mosquito.backend.named("testing")

  getter config = {
    "year" => "1752",
    "name" => "the year september lost 12 days"
  }

  getter job_run : Mosquito::JobRun do
    Mosquito::JobRun.new("mock_job_run").tap do |job_run|
      job_run.config = config
      job_run.store
    end
  end

  it "builds the backend key correctly" do
    assert_equal "mosquito:job_run:1", Mosquito::JobRun.config_key "1"
    assert_equal "mosquito:job_run:#{job_run.id}", job_run.config_key
  end

  it "can store and retrieve a job_run with attributes" do
    stored_job_run = Mosquito::JobRun.retrieve job_run.id
    if stored_job_run
      assert_equal config, stored_job_run.config
    else
      flunk "Could not retrieve job_run"
    end
  end

  it "stores job_runs in the backend" do
    stored_job_run = backend.retrieve Mosquito::JobRun.config_key(job_run.id)
    stored_config = stored_job_run.reject! %w|type enqueue_time retry_count|
    assert_equal config, stored_config
  end

  it "can delete a job_run" do
    job_run.delete
    saved_config = Mosquito.backend.retrieve job_run.config_key
    assert_empty saved_config
  end

  it "can set a timed delete on a job_run" do
    ttl = 10
    job_run.delete(in: ttl)
    set_ttl = backend.expires_in job_run.config_key
    assert_equal ttl, set_ttl
  end

  it "can reload a job_run" do
    job_run.reload
  end
end
