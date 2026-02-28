require "../spec_helper"

describe "Mosquito Config" do
  it "allows setting / retrieving the connection string" do
    Mosquito.temp_config do
      Mosquito.configuration.backend_connection_string = "redis://localhost:6379/3"
      assert_equal "redis://localhost:6379/3", Mosquito.configuration.backend_connection_string
    end
  end

  it "enforces missing settings are set" do
    config = Mosquito::Configuration.new
    assert_raises do
      config.validate
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

  it "validates when backend_connection_string is set" do
    Mosquito.temp_config do
      Mosquito.configuration.backend_connection_string = "redis://localhost:6379/3"
      Mosquito.configuration.validate
    end
  end
end
