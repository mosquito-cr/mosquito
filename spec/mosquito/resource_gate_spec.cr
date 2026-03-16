require "../spec_helper"

describe "Mosquito::OpenGate" do
  it "always allows" do
    gate = Mosquito::OpenGate.new
    assert gate.allow?
  end
end

describe "Mosquito::ThresholdGate" do
  it "allows when metric is below threshold" do
    gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 50.0 }
    assert gate.allow?
  end

  it "blocks when metric is at or above threshold" do
    gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 85.0 }
    refute gate.allow?
  end

  it "blocks when metric equals threshold" do
    gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 0.seconds) { 80.0 }
    refute gate.allow?
  end
end

describe "Mosquito::ResourceGate caching" do
  it "caches the check result within TTL" do
    call_count = 0
    gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 5.seconds) do
      call_count += 1
      50.0
    end

    now = Time.utc
    Timecop.freeze(now) do
      gate.allow?
      gate.allow?
      gate.allow?
      assert_equal 1, call_count
    end
  end

  it "re-checks after TTL expires" do
    call_count = 0
    gate = Mosquito::ThresholdGate.new(threshold: 80.0, sample_ttl: 5.seconds) do
      call_count += 1
      50.0
    end

    now = Time.utc
    Timecop.freeze(now) do
      gate.allow?
      assert_equal 1, call_count
    end

    Timecop.freeze(now + 3.seconds) do
      gate.allow?
      assert_equal 1, call_count, "Should still be cached at 3s"
    end

    Timecop.freeze(now + 6.seconds) do
      gate.allow?
      assert_equal 2, call_count, "Should re-check after 6s (past 5s TTL)"
    end
  end
end
