# frozen_string_literal: true

module Enjine
  module Mechanics
    # Counters (CR 122). Any counter name is valid card data: a counter with no rules of its own
    # (oil, charge, lore, ...) is just a marker that abilities can count (CR 122.1). The kinds
    # registered here carry rules of their own:
    #   - power/toughness counters "+X/+Y" / "-X/-Y" (CR 122.1a, layer 7c, 613.4c)
    #   - keyword counters "flying", "hexproof", ... (CR 122.1b, layer 6, 613.1f)
    #   - stun counters stop untapping (CR 122.1d), shield counters protect (CR 122.1c)
    # Replacement and prevention effects of counters run through Engine#propose (CR 614, 615).
    module Counters
      NAME = %r{\A(?:[+-]\d+/[+-]\d+|[a-z][a-z0-9_]*)\z}
      POWER_TOUGHNESS = %r{\A([+-]\d+)/([+-]\d+)\z}
      # CR 122.1b: the keywords a keyword counter can be (those the engine implements).
      KEYWORDS = %i[flying first_strike double_strike deathtouch haste hexproof indestructible lifelink menace reach
                    trample vigilance].freeze

      module_function

      # "first strike" and "First-Strike" are written first_strike.
      def normalize(name)
        return name unless name.is_a?(String) || name.is_a?(Symbol)

        POWER_TOUGHNESS.match?(name.to_s) ? name.to_s : name.to_s.downcase.tr(" -", "__")
      end

      def valid?(name) = name.is_a?(String) && NAME.match?(name)

      # Error message for an invalid counter name, or nil.
      def error(name)
        return nil if valid?(name)

        "must be a counter name: +X/+Y, -X/-Y or a lowercase word (e.g. +1/+1, stun, shield, oil)"
      end

      # [power delta, toughness delta] from all power/toughness counters (CR 122.1a, 613.4c).
      def power_toughness(counters)
        counters.each_with_object([0, 0]) do |(name, n), delta|
          m = POWER_TOUGHNESS.match(name) or next
          delta[0] += Integer(m[1]) * n
          delta[1] += Integer(m[2]) * n
        end
      end

      # Keywords granted by keyword counters (CR 122.1b).
      def keywords(counters)
        counters.filter_map do |name, n|
          name.to_sym if n.positive? && KEYWORDS.include?(name.to_sym) && Enjine.registry.fetch(:keyword, name)
        end
      end

      def any?(counters) = counters.any? { |_, n| n.positive? }

      # Replacement / prevention effects created by the counters on the object a proposal affects.
      def replace!(engine, proposal)
        id = proposal.data[proposal.kind == "damage" ? "target" : "object"]
        obj = id && engine.state.objects[id]
        return unless obj && obj.zone == :battlefield
        return proposal.data["amount"] = 0 if proposal.kind == "damage" && engine.damage_batch&.include?(obj.id)

        obj.counters.each do |name, n|
          kind = Enjine.registry.fetch(:counter, name)
          next unless n.positive? && kind.respond_to?(:replace!) && !proposal.applied.include?("counter:#{name}")

          proposal.applied << "counter:#{name}" # CR 614.5: each replacement applies once
          kind.replace!(engine, obj, proposal)
        end
      end

      # A counter kind with rules (documentation and behavior).
      class Kind < Primitive
        def self.build(_params, _errors, _path, **) = self
      end

      # +1/+1 counters (CR 122.1a). Annihilate with -1/-1 counters as a state-based action (CR 704.5q).
      class PlusOne < Kind
        primitive :counter, :"+1/+1",
                  description: "Adds 1 to power and toughness (layer 7c). Any +X/+Y or -X/-Y counter works the same " \
                               "way. If a permanent has both +1/+1 and -1/-1 counters, N of each are removed as a " \
                               "state-based action (N = the smaller count).",
                  rules: %w[122.1a 122.3 613.4c 704.5q],
                  example: { "add_counters" => { "counter" => "+1/+1", "amount" => 1, "to" => "self" } }
      end

      # -1/-1 counters (CR 122.1a).
      class MinusOne < Kind
        primitive :counter, :"-1/-1", description: "Subtracts 1 from power and toughness (layer 7c).",
                                      rules: %w[122.1a 122.3 613.4c 704.5q],
                                      example: { "add_counters" => { "counter" => "-1/-1", "amount" => 1, "to" => { "target" => 0 } } }
      end

      # Loyalty counters (CR 122.1e, 306.5b).
      class Loyalty < Kind
        primitive :counter, :loyalty, description: "A planeswalker's loyalty; at 0 it is put into its owner's graveyard.",
                                      rules: %w[122.1e 306.5b 704.5i],
                                      example: { "add_counters" => { "counter" => "loyalty", "amount" => 1, "to" => "self" } }
      end

      # Keyword counters (CR 122.1b). Registered once under the name "keyword" for documentation;
      # the counter itself is named after its keyword ("flying", "hexproof", "first_strike", ...).
      class KeywordCounter < Kind
        primitive :counter, :keyword,
                  description: "A counter named after a keyword (#{KEYWORDS.join(", ")}) gives the permanent that " \
                               "keyword (layer 6). Write the keyword itself as the counter name.",
                  rules: %w[122.1b 613.1f],
                  example: { "add_counters" => { "counter" => "hexproof", "amount" => 1, "to" => "self" } }
      end

      # Stun counters (CR 122.1d): "If a permanent with a stun counter on it would become untapped,
      # instead remove a stun counter from it."
      class Stun < Kind
        primitive :counter, :stun,
                  description: "If the permanent would become untapped (untap step or an effect), instead one stun " \
                               "counter is removed from it.",
                  rules: %w[122.1d 502.3 701.26b],
                  example: { "add_counters" => { "counter" => "stun", "amount" => 1, "to" => { "target" => 0 } } }

        def self.replace!(engine, obj, proposal)
          return unless proposal.kind == "untap"

          proposal.data["cancelled"] = true
          engine.remove_counters!(obj, "stun", 1)
        end
      end

      # Finality counters (CR 122.1h): "If this permanent would be put into a graveyard from the
      # battlefield, exile it instead."
      class Finality < Kind
        primitive :counter, :finality,
                  description: "If the permanent would be put into a graveyard from the battlefield, it is exiled instead.",
                  rules: %w[122.1h 614.1a],
                  example: { "enters_with_counters" => { "counters" => { "finality" => 1 } } }

        def self.replace!(_engine, _obj, proposal)
          proposal.data["to"] = :exile if proposal.kind == "zone_change" && proposal.data["to"] == :graveyard
        end
      end

      # Shield counters (CR 122.1c): one replacement effect ("if it would be destroyed as the result of
      # an effect, instead remove a shield counter") and one prevention effect ("if damage would be dealt
      # to it, prevent that damage and remove a shield counter").
      class Shield < Kind
        primitive :counter, :shield,
                  description: "If the permanent would be destroyed by an effect, instead remove a shield counter. If " \
                               "damage would be dealt to it, prevent it and remove a shield counter (simultaneous " \
                               "damage, such as combat damage, removes only one).",
                  rules: %w[122.1c 614.1a 615.1a 701.8b],
                  example: { "add_counters" => { "counter" => "shield", "amount" => 1, "to" => { "target" => 0 } } }

        def self.replace!(engine, obj, proposal)
          case proposal.kind
          when "zone_change"
            return unless proposal.data["reason"] == "destroy" # CR 701.8b: lethal-damage SBAs aren't "an effect"

            proposal.data["cancelled"] = true
            engine.remove_counters!(obj, "shield", 1)
          when "damage"
            prevent_damage!(engine, obj, proposal)
          end
        end

        # CR 615.1a. Damage dealt at the same time by several sources is one event: one counter.
        def self.prevent_damage!(engine, obj, proposal)
          proposal.data["amount"] = 0
          engine.damage_batch&.push(obj.id)
          engine.remove_counters!(obj, "shield", 1)
        end
      end
    end
  end
end
