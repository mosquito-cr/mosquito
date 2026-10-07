module Mosquito
  # ResourceConstraint is an opt-in module that allows jobs to declare
  # which bounded resources they consume (e.g., CPU, GPU, network).
  #
  # These declarations are used by the `Autoscaler` to determine which
  # `ResourceMonitor`s are relevant for scaling decisions.
  #
  # ## Usage
  #
  # ```crystal
  # class GpuRenderJob < Mosquito::QueuedJob
  #   include Mosquito::ResourceConstraint
  #   constrain :gpu
  #
  #   param scene_id : Int32
  #
  #   def perform
  #     # GPU-intensive work
  #   end
  # end
  # ```
  #
  # Multiple constraints can be declared at once:
  #
  # ```crystal
  # class DataPipelineJob < Mosquito::QueuedJob
  #   include Mosquito::ResourceConstraint
  #   constrain :cpu, :network
  #   # ...
  # end
  # ```
  module ResourceConstraint
    # Global registry mapping job class names to their resource constraints.
    @@global_registry = {} of String => Array(String)

    # Returns the global registry of all resource constraints.
    def self.registry : Hash(String, Array(String))
      @@global_registry
    end

    # Returns the set of all unique resource names declared across all
    # constrained jobs.
    def self.all_constraints : Set(String)
      result = Set(String).new
      @@global_registry.each_value do |constraints|
        constraints.each { |c| result << c }
      end
      result
    end

    macro included
      extend Mosquito::ResourceConstraint::ClassMethods
      @@_resource_constraints = [] of String
    end

    module ClassMethods
      # Declares one or more resource constraints for this job.
      #
      # Resources are identified by symbol (e.g., `:cpu`, `:gpu`, `:network`).
      # These are matched against `ResourceMonitor#name` by the `Autoscaler`.
      def constrain(*resources : Symbol) : Nil
        resources.each do |resource|
          name = resource.to_s
          unless @@_resource_constraints.includes?(name)
            @@_resource_constraints << name
          end
        end
        Mosquito::ResourceConstraint.registry[self.name.underscore] = @@_resource_constraints
      end

      # Returns the resource constraints declared for this job.
      def resource_constraints : Array(String)
        @@_resource_constraints
      end
    end
  end
end
