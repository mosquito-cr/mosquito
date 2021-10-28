require "../test_helper"

describe Mosquito::RedisBackend do
  describe "queue_names" do
    it "builds a waiting queue" do
      skip
    end

    it "builds a scheduled queue" do
      skip
    end

    it "builds a pending queue" do
      skip
    end

    it "builds a dead queue" do
      skip
    end
  end

  describe "hash storage" do
    it "can store" do
      skip
    end

    it "can retrieve" do
      skip
    end
  end

  describe "delete" do
    it "deletes immediately" do
      skip
    end

    it "deletes at a ttl" do
      skip
    end
  end

  describe "list_queues" do
    it "de-dups the queue list" do
      skip
    end

    it "includes queues prefixed with scheduled and waiting but not dead" do
      skip
    end
  end

  describe "self.flush" do
    it "wipes the database" do
      skip
    end
  end

  describe "schedule" do
    it "adds a task to the schedule_q at the time" do
      skip
    end
  end

  describe "deschedule" do
    it "checks the scheduled q for tasks due to run soon" do
      skip
    end

    it "returns a blank array when no tasks exist" do
      skip
    end

    it "doesn't return tasks which aren't yet due" do
      skip
    end
  end

  describe "enqueue" do
    it "puts a task on the waiting_q" do
      skip
    end
  end

  describe "dequeue" do
    it "returns a task object when one is waiting" do
      skip
    end

    it "moves the task from waiting to pending" do
      skip
    end

    it "returns nil when nothing is waiting" do
      skip
    end
  end

  describe "finish" do
    it "removes the task from the pending queue" do
      skip
    end
  end

  describe "terminate" do
    it "adds a task to the dead queue" do
      skip
    end
  end

  describe "flush" do
    it "cleans the waiting_q" do
      skip
    end

    it "cleans the pending_q" do
      skip
    end

    it "cleans the scheduled_q" do
      skip
    end

    it "cleans the dead_q" do
      skip
    end
  end

  describe "size" do
    it "returns the size of the named q" do
      skip
    end
  end
end
