require "../test_helper"

describe "Mosquito Config" do
  it "allows setting / retrieving the redis url" do
    Mosquito.temp_config(redis_url: "yolo") do
      assert_equal "yolo", Mosquito.settings.redis_url
    end
  end

  it "enforces missing settings are set" do
  end

  it "allows setting idle_wait as a float" do
    test_value = 2.4
    Mosquito.temp_config do
      Mosquito.settings.idle_wait = test_value
      assert_equal test_value, Mosquito.settings.idle_wait
    end
  end

  it "allows setting idle_wait as a time span" do
    test_value = 2.seconds

    Mosquito.temp_config do
      Mosquito.settings.idle_wait = test_value
      assert_equal test_value.total_seconds, Mosquito.settings.idle_wait
    end
  end

  it "allows setting successful_job_ttl" do
    test_value = 2

    Mosquito.temp_config do
      Mosquito.settings.successful_job_ttl = test_value
      assert_equal test_value, Mosquito.settings.successful_job_ttl
    end
  end

  it "allows setting failed_job_ttl" do
    test_value = 2

    Mosquito.temp_config do
      Mosquito.settings.failed_job_ttl = test_value
      assert_equal test_value, Mosquito.settings.failed_job_ttl
    end
  end
end
