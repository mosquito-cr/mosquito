require "../test_helper"

describe Mosquito::Base do
  it "keeps a list of scheduled tasks" do
    Base.bare_mapping do
      Base.register_job_interval PeriodicTestJob, 1.minute
      assert_equal PeriodicTestJob, Base.scheduled_tasks.first.class
    end
  end

  it "correctly maps job classes from type strings" do
    Base.bare_mapping do
      Base.register_job_mapping "fizzbuzz", QueuedTestJob
      assert_equal QueuedTestJob, Base.job_for_type "fizzbuzz"
    end
  end
end
