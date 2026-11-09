# frozen_string_literal: true

module Enjine
  module Mechanics
    class Amount
      # {"mana_spent": {"of": ..., "color": "W" | "colors": true}}: the mana spent to cast a spell (CR 601.2h),
      # recorded by type as it was paid (an "any type" payment counts as the mana's real type, CR 609.4b):
      #   no option        the total amount of mana spent ("X is the amount of mana spent to cast it")
      #   "color": "W"     how much of one type was spent ("if {W}{W} was spent": at_least 2; "C" for colorless)
      #   "colors": true   how many colors were spent (converge, CR 207.2c; colorless mana is no color, CR 105.1)
      # `of` is whose: "self" (default) is this spell, or the permanent this card became as a resolving spell
      # (CR 400.7d; its triggered abilities remember it once it has left); {"triggering": "object"} is the
      # spell a "whenever you cast" trigger is about, as it was cast; {"target": n} is a target spell. Nothing
      # was spent on an object that wasn't cast, and a copy of a spell had no mana spent on it (CR 707.10).
      class ManaSpent
        OF = "\"self\", {\"triggering\": \"object\"} or {\"target\": n}"

        def self.build(data, errors, path, targets_count:, results_count: 0)
          errors << "#{path}: must be an object" unless data.is_a?(Hash)
          data = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
          Mechanics.check_keys(data, %w[of color colors], errors, path)
          of = Selector.build(data.fetch("of", "self"), errors, "#{path}.of", targets_count: targets_count,
                                                                              results_count: results_count)
          errors << "#{path}.of: must be #{OF}" if of && !(%i[self target].include?(of.kind) || of.value == "object")
          color = data["color"]
          errors << "#{path}.color: must be one of #{Mana::TYPES.join(", ")}" unless color.nil? || Mana::TYPES.map(&:to_s).include?(color)
          errors << "#{path}: color and colors can't be used together" if color && data["colors"]
          errors << "#{path}.colors: must be true" unless [nil, true].include?(data["colors"])
          new(of, color, data["colors"] == true)
        end

        def initialize(whose, color, colors)
          @of = whose
          @color = color
          @colors = colors
          freeze
        end

        def value(engine, ctx)
          spent = ManaSpent.spent(engine, ctx, @of) || []
          return (spent.uniq & Keywords::Sunburst::COLORS).size if @colors
          return spent.count(@color) if @color

          spent.size
        end

        def to_s
          what = if @colors then "the number of colors of mana"
                 elsif @color then "the amount of {#{@color}}"
                 else "the amount of mana"
                 end
          "#{what} spent to cast #{@of&.kind == :self ? "it" : @of}"
        end

        # The mana types spent on the object `whose` (the `of` selector) names, or nil when none was recorded.
        def self.spent(engine, ctx, whose)
          case whose&.kind
          when :target then engine.state.objects[ctx.targets&.[](whose.value)]&.mana_spent
          when :triggering then Selector.memory(engine, ctx).dig("triggering", "mana_spent")
          else own(engine, ctx)
          end
        end

        # "This spell" while it resolves (or as it enters), else the source permanent, else what the resolving
        # triggered ability remembers of a source that has left (CR 603.4, 608.2h).
        def self.own(engine, ctx)
          holder = engine.state.objects[ctx.object]
          return holder.mana_spent if holder && !holder.ability?

          source = engine.state.objects[ctx.source]
          return source.mana_spent if source && !source.ability? && %i[battlefield stack].include?(source.zone)

          holder&.memory&.[]("source_mana_spent")
        end
      end
    end
  end
end
