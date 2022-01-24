module Mosquito
  class Base
    # Testing wedge which wipes out the Task mapping for the
    # duration of the block.
    def self.bare_mapping(&block)
      scheduled_tasks = @@scheduled_tasks
      @@scheduled_tasks = [] of PeriodicTask

      mapping = @@mapping
      @@mapping = {} of String => Job.class

      yield

    ensure
      @@mapping = mapping unless mapping.nil?
      @@scheduled_tasks = scheduled_tasks unless scheduled_tasks.nil?
    end
  end
end

