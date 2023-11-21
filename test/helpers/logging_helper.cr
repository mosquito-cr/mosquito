require "log"

class TestingLogBackend < Log::MemoryBackend
  def self.instance
    @@instance ||= new
  end

  def clear
    @entries.clear
  end
end

class Minitest::Test
  def logs
    TestingLogBackend.instance.entries
      .map(&.message)
      .map(&.gsub(/\e\[\d+(;\d+)?m/, "")) # remove color codes
  end

  private def logs_match(expected : Regex) : Bool
    matched = logs.any? do |entry|
      entry =~ expected
    end
  end

  def assert_logs_match(expected : String)
    assert_logs_match %r|#{expected}|
  end

  def assert_logs_match(expected : Regex)
    assert logs_match(expected), "Expected to logs to include #{expected}. Logs contained: \n#{logs.join("\n")}"
  end

  def refute_logs_match(expected : String)
    refute_logs_match %r|#{expected}|
  end

  def refute_logs_match(expected : Regex)
    refute logs_match(expected), "Expected to logs to not include #{expected}. Logs contained: \n#{logs.join("\n")}"
  end

  def clear_logs
    TestingLogBackend.instance.clear
  end
end

Log.setup do |config|
  config.bind "*", :debug, TestingLogBackend.instance
  config.bind "redis.*", :warn, TestingLogBackend.instance
  config.bind "mosquito.*", :trace, TestingLogBackend.instance
end
