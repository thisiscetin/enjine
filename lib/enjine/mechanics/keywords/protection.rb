# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "Hexproof from [quality]" and "protection from [quality]" (CR 702.11d, 702.16): static abilities of a
      # permanent whose quality is a card spec matched against the spell, or the source of the ability or
      # damage, as it is now ({"colors": ["B"]} "from black", {"types": ["instant"]} "from instants",
      # {"color_count": {"equal": 1}} "from monocolored"); "everything" is protection from everything (CR
      # 702.16j). "From A and from B" is two abilities (CR 702.11f, 702.16g). The engine asks for them by kind
      # (Engine::Rules#protected_from?).
      class QualityAbility < Primitive
        attr_reader :quality

        # Its value may be the string "everything".
        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          new(params == "everything" ? CardSpec::ANY : CardSpec.build(params, errors, path))
        end

        def initialize(quality)
          super()
          @quality = quality
          freeze
        end

        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def everything? = quality.equal?(CardSpec::ANY)

        # Whether `object` (a spell, or the source of an ability or of damage) has the quality.
        def from?(engine, object) = !object.nil? && quality.match?(engine, object)

        def quality_text = everything? ? "everything" : quality.to_s.delete_suffix(" card")
      end

      # Hexproof from [quality] (CR 702.11d): it can't be the target of [quality] spells its controller's
      # opponents control, or of abilities they control from [quality] sources.
      class HexproofFrom < QualityAbility
        primitive :ability, :hexproof_from,
                  description: "Hexproof from the quality: this permanent can't be the target of spells with the " \
                               "quality, or abilities from sources with it, that its controller's opponents control. " \
                               "The quality is a card spec (`{\"colors\": [\"B\"]}`, `{\"types\": [\"instant\"]}`, " \
                               "`{\"color_count\": {\"equal\": 1}}` for monocolored).",
                  rules: %w[702.11d 702.11f 115.4],
                  params: { "(value)" => "card spec of the quality" },
                  example: { "hexproof_from" => { "colors" => ["B"] } }

        def kind = :hexproof_from
        def to_s = "Hexproof from #{quality_text}"
      end

      # Protection from [quality] (CR 702.16b-f, "DEBT"): it can't be targeted by spells with the quality or
      # abilities from sources with it, enchanted or equipped by Auras and Equipment with it, or blocked by
      # creatures with it, and damage sources with it would deal to it is prevented.
      class ProtectionFrom < QualityAbility
        primitive :ability, :protection_from,
                  description: "Protection from the quality (a card spec, or \"everything\"): damage from sources " \
                               "with the quality is prevented, and this permanent can't be enchanted or equipped " \
                               "by, blocked by or targeted by anything with the quality (Auras and Equipment " \
                               "already attached fall off as a state-based action).",
                  rules: %w[702.16a 702.16b 702.16c 702.16d 702.16e 702.16f 702.16g 702.16j 704.5m 704.5n],
                  params: { "(value)" => "card spec of the quality, or \"everything\"" },
                  example: { "protection_from" => { "colors" => ["W"] } }

        def kind = :protection_from
        def to_s = "Protection from #{quality_text}"
      end
    end
  end
end
