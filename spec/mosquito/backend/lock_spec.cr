require "../../spec_helper"

describe "distributed locking" do
  getter key : String { "testing:backend:lock" }
  getter instance_id : String { "abcd" }
  getter ttl : Time::Span { 1.second }

  def ensure_unlock(&block)
    yield
    Mosquito.backend.delete key
  end

  it "locks" do
    ensure_unlock do
      got_it = Mosquito.backend.lock? key, instance_id, ttl
      assert got_it
    end
  end

  it "doesn't double lock" do
    ensure_unlock do
      hold = Mosquito.backend.lock? key, "abcd", ttl
      assert hold

      try = Mosquito.backend.lock? key, "wxyz", ttl
      refute try
    end
  end

  it "locks after unlock" do
    ensure_unlock do
      hold = Mosquito.backend.lock? key, "abcd", ttl
      assert hold

      Mosquito.backend.unlock key, instance_id

      try = Mosquito.backend.lock? key, "wxyz", ttl
      assert try
    end
  end

  it "renews a lock held by the same instance" do
    ensure_unlock do
      hold = Mosquito.backend.lock? key, instance_id, ttl
      assert hold

      renewed = Mosquito.backend.renew_lock? key, instance_id, ttl
      assert renewed
    end
  end

  it "doesn't renew a lock held by another instance" do
    ensure_unlock do
      hold = Mosquito.backend.lock? key, "abcd", ttl
      assert hold

      renewed = Mosquito.backend.renew_lock? key, "wxyz", ttl
      refute renewed
    end
  end

  it "doesn't renew a lock that doesn't exist" do
    ensure_unlock do
      renewed = Mosquito.backend.renew_lock? key, instance_id, ttl
      refute renewed
    end
  end
end
