# frozen_string_literal: true

module Enjine
  module Mechanics
    class Amount
      # {"mana_spent": {"of": ..., "color": "W" | "colors": true}}: the mana spent to cast a spell (CR 601.2h),
      # recorded by type as it was paid (an "any type" payment counts as the mana's real type, CR 609.4b):
      #   no option        the total amount of mana spent ("X is the amount of mana spent to cast it")
      #   "color": "W"     how much of one type was spent ("if {W}{W} was spent": at_least 2; "C" for colorless)
      #   "colors": true   how many colors were spent (converge, CR 207.2c; colorless mana is no color, CR 105.1)
      #   "from": spec     how much came from sources matching a card spec ("if mana from a Treasure was spent":
      #                    {"subtypes": ["treasure"]}), as they were when they made it (Engine::ManaSources)
      # `of` is whose: "self" (default) is this spell, or the permanent this card became as a resolving spell
      # (CR 400.7d; its triggered abilities remember it once it has left); {"triggering": "object"} is the
      # spell a "whenever you cast" trigger is about, as it was cast; {"target": n} is a target spell. Nothing
      # was spent on an object that wasn't cast, and a copy of a spell had no mana spent on it (CR 707.10).
      class ManaSpent
        OF = "\"self\", {\"triggering\": \"object\"} or {\"target\": n}"

        def self.build(data, errors, path, targets_count:, results_count: 0)
          errors << "#{path}: must be an object" unless data.is_a?(Hash)
          data = data.is_a?(Hash) ? data.transform_keys(&:to_s) : {}
          Mechanics.check_keys(data, %w[of color colors from], errors, path)
          of = Selector.build(data.fetch("of", "self"), errors, "#{path}.of", targets_count: targets_count,
                                                                              results_count: results_count)
          errors << "#{path}.of: must be #{OF}" if of && !(%i[self target].include?(of.kind) || of.value == "object")
          color = data["color"]
          errors << "#{path}.color: must be one of #{Mana::TYPES.join(", ")}" unless color.nil? || Mana::TYPES.map(&:to_s).include?(color)
          errors << "#{path}: color and colors can't be used together" if color && data["colors"]
          errors << "#{path}.colors: must be true" unless [nil, true].include?(data["colors"])
          errors << "#{path}: from can't be used with color or colors" if data.key?("from") && (color || data["colors"])
          from = data.key?("from") ? CardSpec.build(data["from"], errors, "#{path}.from") : nil
          new(of, color, data["colors"] == true, from)
        end

        def initialize(whose, color, colors, from = nil)
          @of = whose
          @color = color
          @colors = colors
          @from = from
          freeze
        end

        def value(engine, ctx)
          return from_count(engine, ctx) if @from

          spent = ManaSpent.spent(engine, ctx, @of) || []
          return (spent.uniq & Keywords::Sunburst::COLORS).size if @colors
          return spent.count(@color) if @color

          spent.size
        end

        def to_s
          what = if @colors then "the number of colors of mana"
                 elsif @color then "the amount of {#{@color}}"
                 elsif @from then "the amount of mana from a #{@from.to_s.delete_suffix(" card")} source"
                 else "the amount of mana"
                 end
          "#{what} spent to cast #{@of&.kind == :self ? "it" : @of}"
        end

        # How much of the mana spent came from sources matching `from` (their characteristics then, CR 106.6).
        def from_count(engine, ctx)
          sources = ManaSpent.spent(engine, ctx, @of, key: "mana_from") || []
          sources.count { @from.chars_match?(engine, Engine::ManaSources.source_chars(it)) }
        end

        # The mana types spent on the object `whose` (the `of` selector) names, or nil when none was recorded.
        # `key` "mana_from": instead, the remembered sources of the mana that came from artifacts.
        def self.spent(engine, ctx, whose, key: "mana_spent")
          case whose&.kind
          when :target # a spell the resolving one countered: as it last existed (Engine::TurnHistory#remember_spell!)
            ref = ctx.targets&.[](whose.value)
            obj = engine.state.objects[ref]
            obj ? recorded(obj, key) : engine.resolving_last_known(ref)&.[](key)
          when :triggering then Selector.memory(engine, ctx).dig("triggering", key)
          else own(engine, ctx, key)
          end
        end

        # What `obj` recorded as it was cast: its mana spent (an attribute) or the mana's sources (memory).
        def self.recorded(obj, key) = key == "mana_spent" ? obj.mana_spent : obj.memory[key]

        # "This spell" while it resolves (or as it enters), else the source permanent, else what the resolving
        # triggered ability remembers of a source that has left (CR 603.4, 608.2h).
        def self.own(engine, ctx, key = "mana_spent")
          holder = engine.state.objects[ctx.object]
          return recorded(holder, key) if holder && !holder.ability?

          source = engine.state.objects[ctx.source]
          return recorded(source, key) if source && !source.ability? && %i[battlefield stack].include?(source.zone)

          holder&.memory&.[]("source_#{key}")
        end
      end
    end
  end
end
