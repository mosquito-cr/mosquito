require "../../spec_helper"

describe "Mosquito::Runners::Overseer" do
  getter(executor_pipeline) { Channel(Tuple(JobRun, Queue)).new }
  getter(idle_notifier) { Channel(Bool).new }
  getter(queue_list) { MockQueueList.new }
  getter(coordinator) { MockCoordinator.new queue_list }
  getter(executor) { MockExecutor.new executor_pipeline, idle_notifier }

  getter(overseer : MockOverseer) {
    MockOverseer.new.tap do |o|
      o.queue_list = queue_list
      o.coordinator = coordinator
      o.idle_notifier = idle_notifier
      o.executors = [] of Mosquito::Runners::Executor
      o.executor_count.times do
        o.executors << executor.as(Mosquito::Runners::Executor)
      end
    end
  }

  def register(job_class : Mosquito::Job.class)
    Mosquito::Base.register_job_mapping job_class.name.underscore, job_class
    queue_list.queues << job_class.queue
  end

  def run_job(job_class : Mosquito::Job.class)
    register job_class
    job_class.reset_performance_counter!
    job_run = job_class.new.enqueue
    executor.execute job_run, from_queue: job_class.queue
  end

  describe "pre_run" do
    it "runs all executors" do
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Starting, executor.state
      end
      overseer.pre_run
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Working, executor.state
      end
    end
  end

  describe "post_run" do
    it "stops all executors" do
      overseer.executors.each(&.run)
      overseer.post_run
      overseer.executors.each do |executor|
        assert_equal Runnable::State::Finished, executor.state
      end
    end

    it "logs messages about stopping the executors" do
      clear_logs
      overseer.pre_run
      overseer.post_run
      assert_logs_match "Stopping #{overseer.executor_count} executors."
      assert_logs_match "All executors stopped."
    end
  end

  describe "each_run" do
    it "dequeues a job and dispatches it to the pipeline" do
      clean_slate do
        register QueuedTestJob
        expected_job_run = QueuedTestJob.new.enqueue

        overseer.work_handout = Channel(Tuple(JobRun, Queue)).new

        queue_list.state = Runnable::State::Working
        executor.state = Runnable::State::Idle

        # each_run will block until there's a receiver on the channel
        spawn { overseer.each_run }
        actual_job_run, queue = overseer.work_handout.receive
        assert_equal expected_job_run, actual_job_run
        assert_equal QueuedTestJob.queue, queue
      end
    end

    it "waits #idle_wait before checking the queue again" do
      clean_slate do
        # an idle executor, but no jobs in the queue
        executor.state = Runnable::State::Idle
        queue_list.state = Runnable::State::Working

        tick_time = Time.measure do
          overseer.each_run
        end

        assert_in_epsilon(
          overseer.idle_wait.total_seconds,
          tick_time.total_seconds,
          epsilon: 0.05
        )
      end
    end

    it "triggers the scheduler" do
      assert_equal 0, coordinator.schedule_count
      overseer.each_run
      assert_equal 1, coordinator.schedule_count
    end
  end
end
