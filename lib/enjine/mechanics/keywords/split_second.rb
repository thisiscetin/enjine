# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # Split second (CR 702.61a-b): "As long as this spell is on the stack, players can't cast other spells or
      # activate abilities that aren't mana abilities." Mana abilities and special actions stay legal, and
      # triggered abilities still trigger and are put on the stack (CR 702.61c). It's a keyword a spell has on
      # the stack, so `spell_keywords` can grant it ("instant and sorcery spells you control have split second").
      # The rules code asks SplitSecond.active? (Engine::Rules#cast_forbidden?, Engine::Casting#activatable?), so
      # it also stops casting while another object resolves (a `cast` effect, cascade, suspend).
      class SplitSecond < Primitive
        primitive :keyword, :split_second,
                  description: "As long as this spell is on the stack, players can't cast spells or activate " \
                               "abilities that aren't mana abilities (mana abilities, special actions and triggered " \
                               "abilities still work).",
                  rules: %w[702.61a 702.61b 702.61c], example: { "keywords" => ["split second"] }

        # Whether a spell with split second is on the stack (CR 702.61b).
        def self.active?(engine)
          engine.state.stack.any? do |id|
            obj = engine.state.objects[id]
            obj && !obj.ability? && engine.chars(obj).keyword?(:split_second)
          end
        end
      end
    end
  end
end
