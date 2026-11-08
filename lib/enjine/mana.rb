# frozen_string_literal: true

module Enjine
  # Mana symbols, colors and mana costs (CR 106, 107.4, 202).
  module Mana
    COLORS = %i[W U B R G].freeze
    # Every type of mana that can sit in a mana pool: five colors plus colorless (CR 106.1).
    TYPES = (COLORS + [:C]).freeze
    SYMBOL = /\{([^{}]*)\}/

    def self.empty_pool
      TYPES.to_h { |t| [t, 0] }
    end

    # A parsed mana cost such as "{2}{R}{R}".
    Cost = Data.define(:generic, :colored) do
      def self.parse(text)
        errors = []
        cost = Mana.parse_cost(text, errors)
        raise ArgumentError, errors.join(", ") unless errors.empty?

        cost
      end

      # Mana value (CR 202.3).
      def mana_value = generic + colored.values.sum

      def to_s
        parts = []
        parts << "{#{generic}}" if generic.positive? || colored.empty?
        colored.each { |c, n| parts.concat(["{#{c}}"] * n) }
        parts.join
      end
    end

    # Parses a mana cost string; pushes problems into errors and returns a Cost (or nil).
    def self.parse_cost(text, errors, path = "mana_cost")
      unless text.is_a?(String)
        errors << "#{path}: must be a string like \"{1}{G}\""
        return nil
      end

      rest = text.gsub(SYMBOL, "")
      unless rest.empty?
        errors << "#{path}: unexpected characters in #{text.inspect}"
        return nil
      end

      generic = 0
      colored = {}
      text.scan(SYMBOL).flatten.each do |sym|
        case sym
        when /\A\d+\z/ then generic += sym.to_i
        when "W", "U", "B", "R", "G", "C" then colored[sym.to_sym] = colored.fetch(sym.to_sym, 0) + 1
        else errors << "#{path}: unsupported mana symbol {#{sym}}"
        end
      end
      Cost.new(generic: generic, colored: colored.freeze)
    end

    # Parses produced mana such as "{G}" or "{C}{C}" into an Array of pool types.
    def self.parse_produce(text, errors, path)
      unless text.is_a?(String) && !text.empty?
        errors << "#{path}: must be a string like \"{G}\""
        return nil
      end
      unless text.gsub(SYMBOL, "").empty?
        errors << "#{path}: unexpected characters in #{text.inspect}"
        return nil
      end

      symbols = text.scan(SYMBOL).flatten
      bad = symbols.reject { |s| TYPES.include?(s.to_sym) }
      unless bad.empty?
        errors << "#{path}: unsupported produced mana #{bad.map { "{#{it}}" }.join}"
        return nil
      end

      symbols.map(&:to_sym).freeze
    end
  end
end
