require "../../spec_helper"

describe Mosquito::Api::PeriodicJob do
  getter interval : Time::Span = 2.minutes

  describe "publish context" do
    it "includes the periodic job name" do
      clean_slate do
        Mosquito::Base.register_job_interval PeriodicTestJob, interval: interval
        job_run = Mosquito::Base.scheduled_job_runs.first
        observer = job_run.observer
        assert_equal "periodic_job:PeriodicTestJob", observer.publish_context.context
        assert_equal "mosquito:periodic_job:PeriodicTestJob", observer.publish_context.originator
      end
    end
  end

  it "can fetch a list of periodic jobs" do
    clean_slate do
      Mosquito::Base.register_job_interval PeriodicTestJob, interval: interval
      periodic_jobs = Mosquito::Api::PeriodicJob.all
      assert_equal 1, periodic_jobs.size
      assert_equal "PeriodicTestJob", periodic_jobs.first.name
      assert_equal interval, periodic_jobs.first.interval
    end
  end

  it "returns nil for last_executed_at when never run" do
    clean_slate do
      Mosquito::Base.register_job_interval PeriodicTestJob, interval: interval
      periodic_jobs = Mosquito::Api::PeriodicJob.all
      assert_nil periodic_jobs.first.last_executed_at
    end
  end

  it "returns the last executed time after a job runs" do
    now = Time.utc.at_beginning_of_second
    clean_slate do
      Mosquito::Base.register_job_interval PeriodicTestJob, interval: interval
      job_run = Mosquito::Base.scheduled_job_runs.first

      Timecop.freeze(now) do
        job_run.try_to_execute
      end

      periodic_jobs = Mosquito::Api::PeriodicJob.all
      assert_equal now, periodic_jobs.first.last_executed_at
    end
  end

  it "publishes an event when a periodic job is enqueued" do
    now = Time.utc.at_beginning_of_second
    clean_slate do
      Mosquito::Base.register_job_interval PeriodicTestJob, interval: interval

      eavesdrop do
        Timecop.freeze(now) do
          Mosquito::Base.scheduled_job_runs.first.try_to_execute
        end
      end

      assert_message_received /enqueued/
    end
  end
end
