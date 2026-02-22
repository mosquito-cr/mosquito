require "../../spec_helper"

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

  describe "timestamp retrieval" do
    # the job run timestamps are stored as a unix epoch with millis, so nanosecond precision is lost.
    def at_beginning_of_millisecond(time)
      time - (time.nanosecond.nanoseconds) + (time.millisecond.milliseconds)
    end

    it "retrieves started_at and finished_at timestamps" do
      now = at_beginning_of_millisecond Time.utc
      job_run = create_job_run
      Timecop.freeze now do
        job_run.run
      end

      retrieved = Mosquito::JobRun.retrieve job_run.id
      if retrieved
        assert_equal now, retrieved.started_at
        assert_equal now, retrieved.finished_at
      else
        flunk "Could not retrieve job_run"
      end
    end

    it "does not include timestamps in config after retrieve" do
      job_run = create_job_run
      job_run.run

      retrieved = Mosquito::JobRun.retrieve job_run.id
      if retrieved
        refute retrieved.config.has_key?("started_at")
        refute retrieved.config.has_key?("finished_at")
      else
        flunk "Could not retrieve job_run"
      end
    end

    it "retrieves nil timestamps for unexecuted job runs" do
      retrieved = Mosquito::JobRun.retrieve job_run.id
      if retrieved
        assert_nil retrieved.started_at
        assert_nil retrieved.finished_at
      else
        flunk "Could not retrieve job_run"
      end
    end
  end

  it "persists overseer_id via claimed_by and retrieves it" do
    test_overseer = MockOverseer.new
    job_run.claimed_by test_overseer
    retrieved = Mosquito::JobRun.retrieve job_run.id
    assert retrieved
    assert_equal test_overseer.observer.instance_id, retrieved.not_nil!.overseer_id
  end

  it "round-trips overseer_id through store and retrieve" do
    test_overseer = MockOverseer.new
    job_run.claimed_by test_overseer
    job_run.store

    retrieved = Mosquito::JobRun.retrieve job_run.id
    assert retrieved
    assert_equal test_overseer.observer.instance_id, retrieved.not_nil!.overseer_id
  end
end
