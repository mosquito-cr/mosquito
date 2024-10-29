require "../spec_helper"

describe "Mosquito Config" do
  it "allows setting / retrieving the redis url" do
    Mosquito.temp_config(redis_url: "yolo") do
      assert_equal "yolo", Mosquito.configuration.redis_url
    end
  end

  it "enforces missing settings are set" do
    Mosquito.temp_config(redis_url: nil) do
      assert_raises do
        Mosquito.configuration.validate
      end
    end
  end

  it "allows setting idle_wait as a float" do
    test_value = 2.4
    Mosquito.temp_config do
      Mosquito.configuration.idle_wait = test_value
      assert_equal test_value.seconds, Mosquito.configuration.idle_wait
    end
  end

  it "allows setting idle_wait as a time span" do
    test_value = 2.seconds

    Mosquito.temp_config do
      Mosquito.configuration.idle_wait = test_value
      assert_equal test_value, Mosquito.configuration.idle_wait
    end
  end

  it "allows setting successful_job_ttl" do
    test_value = 2

    Mosquito.temp_config do
      Mosquito.configuration.successful_job_ttl = test_value
      assert_equal test_value, Mosquito.configuration.successful_job_ttl
    end
  end

  it "allows setting failed_job_ttl" do
    test_value = 2

    Mosquito.temp_config do
      Mosquito.configuration.failed_job_ttl = test_value
      assert_equal test_value, Mosquito.configuration.failed_job_ttl
    end
  end

  it "allows setting global_prefix string" do
    test_value = "yolo"

    Mosquito.temp_config do
      Mosquito.configuration.global_prefix = test_value
      assert_equal test_value, Mosquito.configuration.global_prefix
      Mosquito.configuration.backend.build_key("test").must_equal "yolo:mosquito:test"
    end
  end

  it "allows setting global_prefix nillable" do
    test_value = nil

    Mosquito.temp_config do
      Mosquito.configuration.global_prefix = test_value
      assert_equal test_value, Mosquito.configuration.global_prefix
      Mosquito.configuration.backend.build_key("test").must_equal "mosquito:test"
    end
  end
end
