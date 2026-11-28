# frozen_string_literal: true

module Enjine
  # Deep copies of state data (Snapshot.load, State#to_h).
  module Snapshot
    module_function

    # An independent deep copy, equal to a Marshal round trip of the value (every String a fresh unfrozen copy) but
    # several times faster on the plain data state holds: Hashes, Arrays, Strings, numbers, symbols, true, false, nil.
    # Anything else (a subclass, a Hash with a default or compared by identity) takes the Marshal round trip.
    def deep_copy(value)
      if value.instance_of?(Hash) && value.default.nil? && value.default_proc.nil? && !value.compare_by_identity?
        value.to_h { |k, v| [deep_copy(k), deep_copy(v)] }
      elsif value.instance_of?(Array) then value.map { deep_copy(it) }
      elsif value.instance_of?(String) then value.dup
      elsif PLAIN.any? { value.instance_of?(it) } then value
      else Marshal.load(Marshal.dump(value))
      end
    end

    PLAIN = [Integer, Float, Symbol, TrueClass, FalseClass, NilClass].freeze
  end
end
