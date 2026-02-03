require "../../spec_helper"

describe Mosquito::Backend do
  getter key : String { "key-#{rand 1000}" }

  it "can calculate an average" do
    backend.average_push key, 10
    backend.average_push key, 20
    backend.average_push key, 30

    assert_equal 20, backend.average key
  end

  it "correctly rolls off old values for the window size" do
    backend.average_push key, 10, window_size: 3
    backend.average_push key, 20, window_size: 3
    backend.average_push key, 30, window_size: 3
    backend.average_push key, 40, window_size: 3
    backend.average_push key, 50, window_size: 3

    assert_equal 40, backend.average key
  end
end
