# frozen_string_literal: true

module Enjine
  class Engine
    # Power and toughness defined by a characteristic-defining ability ("*", CR 604.3), used by the layer pass
    # (Engine::Characteristics) on the battlefield and in every other zone.
    module DefinedPowerToughness
      # CR 604.3, 707.9d: a characteristic-defining power/toughness, unless a copy exception sets them.
      def defined_pt_copied?(obj)
        except = copy_exceptions(obj)
        definition(obj).defined_pt? && !(except&.key?("power") || except&.key?("toughness"))
      end

      # CR 604.3, 613.4a: the defined power/toughness. Its amount may count the object itself ("card types among
      # cards in all graveyards" while it's in one); it can't read power or toughness (CardDefinition#read_pt), so
      # a nested look at the object while it's being computed skips the definition.
      def defined_power_toughness(obj, base, defn)
        return base if (defining = (@defining_pt ||= {})).key?(obj.id)

        defining[obj.id] = ctx = Mechanics::EffectContext.new(obj.controller, obj.id, obj.id, [], [])
        base.with(power: defn.power_amount ? defn.power_amount.value(self, ctx) : base.power,
                  toughness: defn.toughness_amount ? defn.toughness_amount.value(self, ctx) : base.toughness)
      ensure
        @defining_pt.delete(obj.id) if ctx
      end
    end

    include DefinedPowerToughness
  end
end
