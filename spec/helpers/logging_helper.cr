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
  def log_entries
    TestingLogBackend.instance.entries
  end

  def logs
    log_entries.map(&.message)
  end

  COLOR_STRIP = /\e\[\d+(;\d+)?m/

  private def logs_match(expected : Regex) : Bool
    log_entries
      .map(&.message)
      .map(&.gsub(COLOR_STRIP, ""))
      .any? { |entry| entry =~ expected }
  end

  private def logs_match(source : String, match_text : Regex) : Bool
    log_entries
      .select { |entry| entry.source == source }
      .map(&.message)
      .map(&.gsub(COLOR_STRIP, ""))
      .any? { |entry| entry =~ match_text }
  end

  def assert_logs_match(expected : String)
    assert_logs_match %r|#{expected}|
  end

  def assert_logs_match(expected : Regex)
    assert logs_match(expected), "Expected to logs to include #{expected}. Logs contained: \n#{log_entries.map(&.message).join("\n")}"
  end

  def refute_logs_match(expected : String)
    refute_logs_match %r|#{expected}|
  end

  def refute_logs_match(expected : Regex)
    refute logs_match(expected), "Expected to logs to not include #{expected}. Logs contained: \n#{log_entries.map(&.message).join("\n")}"
  end

  def assert_logs_match(source : String, expected : String)
    assert_logs_match source, %r|#{expected}|
  end

  def assert_logs_match(source : String, expected : Regex)
    assert logs_match(source, expected), "Expected to logs to include #{expected}. Logs contained: \n#{log_entries.map{|e| e.source + " " + e.message}.join("\n")}"
  end

  def refute_logs_match(source : String, expected : String)
    refute_logs_match source, %r|#{expected}|
  end

  def refute_logs_match(source : String, expected : Regex)
    refute logs_match(source, expected), "Expected to logs to not include #{expected}. Logs contained: \n#{log_entries.map{|e| e.source + " " + e.message}.join("\n")}"
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
