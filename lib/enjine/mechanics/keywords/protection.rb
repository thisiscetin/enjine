# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "Hexproof from [quality]" and "protection from [quality]" (CR 702.11d, 702.16): static abilities of a
      # permanent whose quality is a card spec matched against the spell, or the source of the ability or
      # damage, as it is now ({"colors": ["B"]} "from black", {"types": ["instant"]} "from instants",
      # {"color_count": {"equal": 1}} "from monocolored"); "everything" is protection from everything (CR
      # 702.16j). "From A and from B" is two abilities (CR 702.11f, 702.16g). Two qualities depend on what has
      # the ability: "each_opponent" (protection from each of your opponents: from everything they control, or own
      # and nobody controls, CR 702.16i, 702.16k) and "its_colors" ("hexproof from each of its colors": anything
      # sharing a color with it, CR 702.11g, 702.16h). The engine asks for them by kind
      # (Engine::Rules#protected_from?).
      class QualityAbility < Primitive
        HOLDER_QUALITIES = %w[each_opponent its_colors].freeze

        attr_reader :quality

        # Its value may be the string "everything", "each_opponent" or "its_colors".
        def self.scalar_params? = true

        def self.build(params, errors, path, **)
          return new(CardSpec::ANY) if params == "everything"
          return new(params.to_sym) if HOLDER_QUALITIES.include?(params)

          if params.is_a?(String)
            errors << "#{path}: must be a card spec, \"everything\", \"each_opponent\" or \"its_colors\""
            return new(CardSpec::ANY)
          end
          new(CardSpec.build(params, errors, path))
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

        # Whether `object` (a spell, or the source of an ability or of damage) has the quality, for `holder` (the
        # permanent with the ability, or the index of the player who has it).
        def from?(engine, object, holder = nil)
          return false if object.nil?

          case quality
          when :each_opponent then QualityAbility.opponents?(object, holder)
          when :its_colors then holder.is_a?(GameObject) && engine.chars(object).colors.intersect?(engine.chars(holder).colors)
          else quality.match?(engine, object)
          end
        end

        # CR 702.16k: the object's controller (or its owner, if nobody controls it) is an opponent of the holder's
        # controller.
        def self.opponents?(object, holder)
          return false if holder.nil?

          (object.controller || object.owner) != (holder.is_a?(Integer) ? holder : holder.controller)
        end

        def quality_text
          case quality
          when :each_opponent then "each of your opponents"
          when :its_colors then "each of its colors"
          else everything? ? "everything" : quality.to_s.delete_suffix(" card")
          end
        end
      end

      # Hexproof from [quality] (CR 702.11d): it can't be the target of [quality] spells its controller's
      # opponents control, or of abilities they control from [quality] sources.
      class HexproofFrom < QualityAbility
        primitive :ability, :hexproof_from,
                  description: "Hexproof from the quality: this permanent can't be the target of spells with the " \
                               "quality, or abilities from sources with it, that its controller's opponents control. " \
                               "The quality is a card spec (`{\"colors\": [\"B\"]}`, `{\"types\": [\"instant\"]}`, " \
                               "`{\"color_count\": {\"equal\": 1}}` for monocolored), or \"its_colors\" (hexproof " \
                               "from each of its colors: whatever shares a color with it).",
                  rules: %w[702.11d 702.11f 702.11g 115.4],
                  params: { "(value)" => "card spec of the quality, or \"its_colors\"" },
                  example: { "hexproof_from" => { "colors" => ["B"] } }

        def kind = :hexproof_from
        def to_s = "Hexproof from #{quality_text}"
      end

      # Protection from [quality] (CR 702.16b-f, "DEBT"): it can't be targeted by spells with the quality or
      # abilities from sources with it, enchanted or equipped by Auras and Equipment with it, or blocked by
      # creatures with it, and damage sources with it would deal to it is prevented.
      class ProtectionFrom < QualityAbility
        primitive :ability, :protection_from,
                  description: "Protection from the quality (a card spec, \"everything\", \"each_opponent\": from " \
                               "each of your opponents, or \"its_colors\"): damage from sources " \
                               "with the quality is prevented, and this permanent can't be enchanted or equipped " \
                               "by, blocked by or targeted by anything with the quality (Auras and Equipment " \
                               "already attached fall off as a state-based action).",
                  rules: %w[702.16a 702.16b 702.16c 702.16d 702.16e 702.16f 702.16g 702.16h 702.16i 702.16j 702.16k
                            704.5m 704.5n],
                  params: { "(value)" => "card spec of the quality, \"everything\", \"each_opponent\" or \"its_colors\"" },
                  example: { "protection_from" => { "colors" => ["W"] } }

        def kind = :protection_from
        def to_s = "Protection from #{quality_text}"
      end
    end
  end
end
