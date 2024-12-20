#
# Fiber-local storage for request state.
#
# Usage:
#
# Current.global(name : Type = default_value)
#
# Current.name # => default_value
# Current.name = new_value
# Current.name # => new_value
#
# Current.reset # resets all globals to their default value.
#
# Warning:
#
# For an application which disposes of and recreates fibers, 
# this will leak memory because there's no way to remove the
# instances which are created for fibers which no longer exist.
#
class Current
  # Fiber-local singleton.
  @@instances : Hash(UInt64, Current) = {} of UInt64 => self
  def self.instance : self
    @@instances[Fiber.current.hash] ||= new
  end

  # :nodoc:
  def reset
    # this method intentionally left blank
  end

  # Reset all instance variables for the current fiber.
  def self.reset
    instance.reset
  end

  macro global(declaration)
    class Current
      def self.{{declaration.var}}
        instance.{{declaration.var}}
      end

      def self.{{declaration.var}}=(value)
        instance.{{declaration.var}} = value
      end

      def reset
        previous_def
        @{{declaration.var}} = {{declaration.value}}
      end

      property {{ declaration.var }} : {{declaration.type}} = {{declaration.value}}
    end
  end
end
