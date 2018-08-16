require "../test_helper"

describe "task rescheduling" do
  @failing_task : Mosquito::Task?
  let(:failing_task) { create_task "failing_job" }

  it "calculates reschedule interval correctly" do
    intervals = {
      1 => 2,
      2 => 8,
      3 => 18,
      4 => 32
    }

    intervals.each do |count, delay|
      task = Mosquito::Task.retrieve(failing_task.id.not_nil!).not_nil!
      task.run
      assert_equal delay.seconds, task.reschedule_interval
    end
  end

  it "prevents rescheduling a job too many times" do
    run_task = -> do
      task = Mosquito::Task.retrieve(failing_task.id.not_nil!).not_nil!
      task.run
      task
    end

    max_reschedules = 4
    max_reschedules.times do
      task = run_task.call
      assert task.rescheduleable?
    end

    task = run_task.call
    refute task.rescheduleable?
  end

  it "counts retries upon failure" do
    assert_equal 0, failing_task.retry_count
    failing_task.run
    assert_equal 1, failing_task.retry_count
  end

  it "updates redis when a failure happens" do
    failing_task.run
    saved_task = Mosquito::Task.retrieve failing_task.id.not_nil!
    assert_equal 1, saved_task.not_nil!.retry_count
  end
end
