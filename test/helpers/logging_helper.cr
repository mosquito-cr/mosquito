class TestingBackend < Log::MemoryBackend
  def self.instance
    @@instance ||= new
  end

  def clear
    @entries.clear
  end
end

class Minitest::Test
  def logs
    TestingBackend.instance.entries
      .map(&.message)
      .join('\n')
      .gsub(/\e\[\d+(;\d+)?m/, "")
  end

  def clear_logs
    TestingBackend.instance.clear
  end
end

Log.builder.bind "*", :debug, TestingBackend.instance
