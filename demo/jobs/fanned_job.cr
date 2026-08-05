# class FannedJob < Mosquito::FanOutInJob
#   param item : Int32
#   param parent : String

#   def branch_out : Array(String)
#     %w|one two three four five six seven eight|
#   end

#   def perform_branch
#     # @branch is something different for each invocation
#     count = Random.rand(1..10)
#     count.times do |i|
#       n = Random.rand(1..10)
#       sleep n
#       log "root: #{@root} branch: #{@branch} step: #{i}/#{count} took #{n} seconds"
#     end
#   end

#   def branch_in
#     # called only when all branches have finished
#     log "#{@root} is all done, mate"
#   end
# end

# FannedJob.new(root: "fizzbuzz-#{Random.rand(1..22)}").enqueue
