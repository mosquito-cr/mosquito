# abstract class Mosquito::FanOutInJob < Mosquito::Job
#   param root : String
#   param fan_state : String = "starting"
#   param parent_job_id : String = ""
#   param branch : String = ""

#   def perform
#     case fan_state
#     when "starting" then dispatch
#     when "finished"
#       branch_in
#       purge_metadata
#     else
#       fan_metadata[job_run_id.not_nil!] = "started"
#       each
#       fan_metadata[job_run_id.not_nil!] = "finished"

#       if all_finished?
#         self.class.new(
#           root: @root.not_nil!,
#           parent_job_id: @parent_job_id.not_nil!,
#           fan_state: "finished"
#         ).enqueue
#       end
#     end
#   end

#   def fan_metadata : Metadata
#     Metadata.new(@parent_job_id.not_nil!)
#   end

#   def my_fan_metadata : Metadata
#     Metadata.new(self.job_run_id.not_nil!)
#   end

#   def purge_metadata
#     fan_metadata.delete
#   end

#   def all_finished? : Bool
#     fan_metadata.to_h.values.all? { |v| v == "finished" }
#   end

#   def dispatch
#     parent_job_id = self.job_run_id.not_nil!
#     fan_info = my_fan_metadata

#     jobs = branch_out.map do |i|
#       self.class
#         .new(
#           root: @root.not_nil!,
#           fan_state: "branch",
#           parent_job_id: parent_job_id,
#           branch: i
#         ).enqueue
#     end

#     jobs.each do |job|
#       fan_info[job.id] = "pending"
#     end

#     log "Enqueued #{jobs.size} jobs: #{jobs.map(&.id).join(", ")}"
#   end

#   # abstract, override in subclass to provide a list of tuples which will be merged with branch metadata and passed to each sub-job
#   abstract def branch_out : Array(String)

#   # abstract, override to do work on each branch
#   abstract def branch_perform : Nil

#   # abstract, override to do something when all branches have finished
#   abstract def finish : Nil
# end
