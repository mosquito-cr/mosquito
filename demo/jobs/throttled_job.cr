# class ThrottledJob < Mosquito::QueuedJob
#   params value : Int32
# 
#   throttle limit: 3, period: 10
# 
#   def perform
#     log "throttled job: #{value}"
# 
#     # For integration testing
#     Mosquito::Redis.instance.incr self.class.name.underscore
#   end
# end
# 
# ThrottledJob.new(1).enqueue
# ThrottledJob.new(2).enqueue
# ThrottledJob.new(3).enqueue
# 
# ThrottledJob.new(1).enqueue
# ThrottledJob.new(2).enqueue
# ThrottledJob.new(3).enqueue
# 
# ThrottledJob.new(1).enqueue
# ThrottledJob.new(2).enqueue
# ThrottledJob.new(3).enqueue
