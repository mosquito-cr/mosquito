require "../test_helper"

describe Mosquito::PeriodicJob do
  it "correctly renders job_type" do
    assert_equal "mosquito::test_jobs::periodic", TestJobs::Periodic.job_type
  end

  it "builds a task" do
    job = TestJobs::Periodic.new
    task = job.build_task

    assert_instance_of Task, task
    assert_equal TestJobs::Periodic.job_type, task.type
  end

  it "is not reschedulable" do
    refute TestJobs::Periodic.new.rescheduleable?
  end

  it "registers in job mapping" do
    assert_equal TestJobs::Periodic, Base.job_for_type(TestJobs::Periodic.job_type)
  end
end
