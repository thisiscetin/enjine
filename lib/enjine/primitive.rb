# frozen_string_literal: true

module Enjine
  # Base class of every mechanic the engine understands.
  #
  # A primitive is a named building block that card data can reference:
  # a card type, supertype, subtype, ability, cost or effect. Each subclass
  # declares its metadata with `primitive`; the declaration both registers it
  # in Enjine.registry and feeds the generated reference docs.
  class Primitive
    CATEGORIES = %i[type supertype subtype keyword ability cost effect filter].freeze

    class << self
      attr_reader :category, :primitive_name, :description, :rules, :params, :example

      # Declares this class as the primitive `name` of `category` and registers it.
      def primitive(category, name, description:, rules: [], params: {}, example: nil)
        raise ArgumentError, "unknown category #{category}" unless CATEGORIES.include?(category)

        @category = category
        @primitive_name = name.to_s
        @description = description
        @rules = rules.freeze
        @params = params.freeze
        @example = example
        Enjine.registry.register(self)
      end
    end
  end

  # Holds every registered primitive, keyed by category and name.
  class Registry
    def initialize
      @entries = Primitive::CATEGORIES.to_h { |c| [c, {}] }
    end

    def register(klass)
      bucket = @entries.fetch(klass.category)
      name = klass.primitive_name
      if bucket.key?(name) && bucket[name] != klass
        raise ArgumentError, "#{klass.category} primitive #{name.inspect} already registered"
      end

      bucket[name] = klass
    end

    def fetch(category, name)
      @entries.fetch(category)[name.to_s]
    end

    def names(category)
      @entries.fetch(category).keys.sort
    end

    def each(category, &)
      @entries.fetch(category).sort.map(&:last).each(&)
    end
  end

  def self.registry
    @registry ||= Registry.new
  end
end
