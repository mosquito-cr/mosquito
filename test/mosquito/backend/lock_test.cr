require "../../test_helper"

describe "distributed locking" do
  let(key) { "testing:backend:lock" }
  let(instance_id) { "abcd" }
  let(ttl) { 1.second }

  it "locks" do
    got_it = Mosquito.backend.lock? key, instance_id, ttl
    assert got_it
    Mosquito.backend.unlock key, instance_id
  end

  it "doesn't double lock" do
    hold = Mosquito.backend.lock? key, "abcd", ttl
    assert hold

    try = Mosquito.backend.lock? key, "wxyz", ttl
    refute try

    Mosquito.backend.unlock key, instance_id
  end

  it "locks after unlock" do
    hold = Mosquito.backend.lock? key, "abcd", ttl
    assert hold

    Mosquito.backend.unlock key, instance_id

    try = Mosquito.backend.lock? key, "wxyz", ttl
    assert try
  end
end
