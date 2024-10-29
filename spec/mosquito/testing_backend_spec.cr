require "../spec_helper"

describe Mosquito::TestBackend do
  def latest_enqueued_job
    Mosquito::TestBackend.enqueued_jobs.last
  end

  it "holds a copy of jobs which have been enqueued" do
    Mosquito.temp_config(backend: Mosquito::TestBackend) do
      QueuedTestJob.new.enqueue
      assert_equal QueuedTestJob, latest_enqueued_job.klass
    end
  end

  it "embeds job parameters" do
    Mosquito.temp_config(backend: Mosquito::TestBackend) do
      EchoJob.new(text: "hello world").enqueue
      assert_equal "hello world", latest_enqueued_job.config["text"]
    end
  end

  it "hold the job id" do
    Mosquito.temp_config(backend: Mosquito::TestBackend) do
      job_run = QueuedTestJob.new.enqueue
      assert_equal job_run.id, latest_enqueued_job.id
    end
  end

  it "has a list of job runs which can be emptied" do
    Mosquito.temp_config(backend: Mosquito::TestBackend) do
      Mosquito::TestBackend.flush_enqueued_jobs!
      job_run = EchoJob.new(text: "hello world").enqueue
      assert_equal job_run.id, latest_enqueued_job.id
      Mosquito::TestBackend.flush_enqueued_jobs!
      assert Mosquito::TestBackend.enqueued_jobs.empty?
    end
  end
end
