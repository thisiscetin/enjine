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

    # A parsed mana cost such as "{2}{R}{R}" or "{X}{R}". `x_symbols` counts the {X} (CR 107.3);
    # their value is announced while casting (CR 601.2b) and is 0 everywhere else (CR 107.3g).
    # `hybrid` lists the hybrid symbols ({R/G}), each as the colors that can pay it (CR 107.4e).
    Cost = Data.define(:generic, :colored, :x_symbols, :hybrid) do
      def initialize(generic:, colored:, x_symbols: 0, hybrid: [].freeze) = super

      def self.parse(text)
        errors = []
        cost = Mana.parse_cost(text, errors)
        raise ArgumentError, errors.join(", ") unless errors.empty?

        cost
      end

      # Mana value (CR 202.3); {X} counts as 0 off the stack (CR 202.3e). A hybrid symbol counts its
      # largest component (CR 202.3f): 1 for {R/G}, 2 for {2/B}.
      def mana_value = generic + colored.values.sum + hybrid.sum { Mana.mono_hybrid?(it) ? 2 : 1 }

      # The cost with X replaced by `value` (CR 107.3a): each {X} adds that much generic mana.
      def with_x(value) = with(generic: generic + (x_symbols * value), x_symbols: 0)

      # The colors of the cost's colored and hybrid symbols, in WUBRG order (CR 202.2, 202.2d, 107.4e).
      def colors = COLORS.select { |c| colored.key?(c) || hybrid.any? { it.include?(c) } }

      # One entry per colored or two-color hybrid symbol: the mana types that can pay it (CR 601.2h). A
      # monocolored hybrid symbol has no single requirement; see #equivalents.
      def requirements = colored.flat_map { |color, n| Array.new(n) { [color] } } + hybrid.reject { Mana.mono_hybrid?(it) }

      # The costs without monocolored hybrid symbols this cost can be paid as (CR 601.2b, 107.4e): each {2/B}
      # as {B} or as {2}. Just itself when it has none.
      def equivalents
        mono, rest = hybrid.partition { Mana.mono_hybrid?(it) }
        return [self] if mono.empty?

        [true, false].repeated_permutation(mono.size).map do |as_color|
          paid = mono.zip(as_color).filter_map { |symbol, color| symbol.last if color }
          with(generic: generic + (2 * (mono.size - paid.size)), hybrid: rest,
               colored: colored.merge(paid.tally) { |_, a, b| a + b })
        end
      end

      def to_s
        parts = ["{X}"] * x_symbols
        parts << "{#{generic}}" if generic.positive? || (colored.empty? && hybrid.empty? && x_symbols.zero?)
        hybrid.each { parts << "{#{it.join("/")}}" }
        colored.each { |c, n| parts.concat(["{#{c}}"] * n) }
        parts.join
      end
    end

    HYBRID = %r{\A([WUBRG2])/([WUBRG])\z}

    # A monocolored hybrid symbol such as {2/B} (CR 107.4e); its first component is the generic "2".
    def self.mono_hybrid?(symbol) = symbol.first.to_s == "2"

    # The sum of several costs (an ability's mana costs, a spell's mana cost plus a kicker cost).
    def self.sum_costs(costs)
      colored = Hash.new(0)
      costs.each { |cost| cost.colored.each { |c, n| colored[c] += n } }
      Cost.new(generic: costs.sum(&:generic), colored: colored.to_h.freeze, x_symbols: costs.sum(&:x_symbols),
               hybrid: costs.flat_map(&:hybrid).freeze)
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
      x = 0
      colored = {}
      hybrid = []
      text.scan(SYMBOL).flatten.each do |sym|
        case sym
        when /\A\d+\z/ then generic += sym.to_i
        when "X" then x += 1
        when "W", "U", "B", "R", "G", "C" then colored[sym.to_sym] = colored.fetch(sym.to_sym, 0) + 1
        when HYBRID then hybrid << hybrid_symbol(sym, errors, path)
        else errors << "#{path}: unsupported mana symbol {#{sym}}"
        end
      end
      Cost.new(generic: generic, colored: colored.freeze, x_symbols: x, hybrid: hybrid.compact.freeze)
    end

    # A hybrid symbol (CR 107.4e), kept in its printed order: two-color such as {R/G} ([:R, :G]) or
    # monocolored such as {2/B} ([:"2", :B]: one black mana or two mana of any type). Phyrexian symbols
    # aren't supported (they are "unsupported mana symbol"s).
    def self.hybrid_symbol(sym, errors, path)
      pair = HYBRID.match(sym).captures.map(&:to_sym)
      return pair.freeze if pair.uniq.size == 2

      errors << "#{path}: {#{sym}} needs two different colors"
      nil
    end

    # Pool types as mana symbols: [:G, :G] -> "{G}{G}".
    def self.symbols(types) = types.map { "{#{it}}" }.join

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
