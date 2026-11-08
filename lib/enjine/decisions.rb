# frozen_string_literal: true

module Enjine
  # Every kind of pending decision. A decision kind is a class with:
  #   .options(engine, pending) -> Array of option Hashes (symbol keys, JSON-safe values)
  #   .submit(engine, pending, option)
  #   .redact(option, viewer_is_decider) -> what another viewer may see of the chosen option
  module Decisions
    KINDS = {} # rubocop:disable Style/MutableConstant -- extension registry

    def self.register(kind, klass)
      KINDS[kind] = klass
    end

    def self.fetch(kind) = KINDS.fetch(kind) { raise ArgumentError, "unknown decision kind #{kind.inspect}" }

    # Base class: options are public unless a subclass says otherwise.
    class Base
      def self.redact(option, _viewer_is_decider) = option
    end
  end
end
