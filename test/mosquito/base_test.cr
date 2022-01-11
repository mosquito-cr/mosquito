require "../test_helper"

describe Mosquito::Base do
  it "has an alias for Models from various ORMs" do
    model_classes = [Granite::Base.new]

    model_classes.each do |model|
      assert model.is_a? Model
    end
  end

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
