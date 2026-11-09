# frozen_string_literal: true

require_relative "../effects/delayed_triggers"

module Enjine
  module Mechanics
    module Abilities
      # Keyword abilities that are alternative costs (CR 118.9, 601.2b, 601.2f-h): "you may cast this card
      # [from a zone] by paying [cost] rather than paying its mana cost". Each is offered as its own cast
      # option, `{type: "cast", object: id, via: "alt:<ability ref>"}`, while the ability functions (the card
      # is in the right zone, and any other condition holds). `cost` is a mana cost string, or a list of
      # costs like kicker's (mana and/or chosen costs such as `tap_permanents`). How a spell was cast is
      # remembered (the `cast_with` / `cast_from` conditions, CR 400.7d). See Engine::AltCasting.
      class AlternativeCost < Primitive
        attr_reader :costs, :mana_cost, :ref_path

        # `{"cost": "{2}{R}"}` or `{"cost": [{"mana": "{2}{R}"}, {"tap_permanents": {...}}]}`.
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          costs = read_costs(raw, errors, path)
          new(costs, path, errors)
        end

        def self.read_costs(raw, errors, path)
          return [] if raw.nil? && optional_cost?

          if raw.nil?
            errors << "#{path}.cost: required"
            return []
          end
          return [Costs::ManaPayment.build(raw, errors, "#{path}.cost")] if raw.is_a?(String)

          costs = StackAbility.parse_costs({ "cost" => raw }, errors, path)
          errors << "#{path}.cost: must be a mana cost string or a non-empty list of costs" if raw.is_a?(Array) && raw.empty?
          costs.each_with_index do |cost, i|
            next if cost.mana? || cost.respond_to?(:choices_needed)

            errors << "#{path}.cost[#{i}]: an alternative cost must be mana or a chosen cost (tap, sacrifice, ...)"
          end
          costs
        end

        def self.optional_cost? = false

        def initialize(costs, path, _errors)
          super()
          @costs = costs.freeze
          @mana_cost = costs.empty? ? nil : Mana.sum_costs(costs.select(&:mana?).map(&:mana_cost))
          @ref_path = path
          freeze
        end

        def kind = :alternative_cost
        def keyword = self.class.primitive_name
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def choosing_costs = costs.reject(&:mana?)

        # The zone the ability lets the card be cast from (CR 113.6).
        def zone = :hand

        # Whether the card `obj` (owned by `index`) may be cast this way now, before timing and cost checks.
        def functions?(_engine, obj, _index) = obj.zone == zone

        # Paid instead of the mana cost? (Mayhem without a cost only allows playing it.)
        def alternative? = !mana_cost.nil?

        # "If the [keyword] cost was paid, exile this card instead of putting it anywhere else any time it would
        # leave the stack."
        def exiles? = false

        # What creature, if any, is returned to its owner's hand as part of the cost: nil, "tapped" (web-slinging)
        # or "unblocked" (sneak).
        def returns = nil

        # Cast "any time you could cast an instant" (sneak).
        def instant_speed? = false

        # "play" also lets a land be played (mayhem without a cost).
        def play = "cast"

        def cost_text = costs.empty? ? "" : " #{costs.join(", ")}"
        def to_s = "#{keyword.split("_").map(&:capitalize).join("-")}#{cost_text}"

        # The cast method (Engine::Permissions) this ability gives.
        def method_for(ref)
          method = { "via" => "alt:#{ref}", "play" => play, "keyword" => keyword }
          return method unless alternative?

          alt = { "cost" => mana_cost.to_s, "ref" => ref }
          alt["exile"] = true if exiles?
          alt["returns"] = returns if returns
          alt["harmonize"] = true if is_a?(Harmonize)
          method["instant"] = true if instant_speed?
          method.merge("alt" => alt)
        end
      end

      # CR 702.34a: flashback, from the graveyard for an instant or sorcery; exiled whenever it would leave the stack.
      class Flashback < AlternativeCost
        primitive :ability, :flashback,
                  description: "Flashback: you may cast this instant or sorcery card from your graveyard by paying " \
                               "`cost` rather than its mana cost; then it's exiled whenever it would leave the stack. " \
                               "`cost` is a mana cost string or a list of costs (`[{\"mana\": \"{1}{U}\"}, " \
                               "{\"tap_permanents\": {\"count\": 3}}]`). Cast option `via: \"alt:<ref>\"`.",
                  rules: %w[702.34a 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "flashback" => { "cost" => "{2}{R}" } }

        def zone = :graveyard
        def exiles? = true
        def allowed_types = %i[instant sorcery]
      end

      # CR 702.180a-b: harmonize, from the graveyard, tapping up to one untapped creature you control to reduce
      # the total cost by its power; exiled whenever it would leave the stack.
      class Harmonize < AlternativeCost
        primitive :ability, :harmonize,
                  description: "Harmonize: you may cast this card from your graveyard by paying `cost` and tapping up " \
                               "to one untapped creature you control rather than its mana cost; the total cost is " \
                               "reduced by generic mana equal to that creature's power. Then it's exiled whenever it " \
                               "would leave the stack. The creature is a `choose_cost` decision (`{type: \"cost\"}` " \
                               "without an object taps none). Cast option `via: \"alt:<ref>\"`.",
                  rules: %w[702.180a 702.180b 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "harmonize" => { "cost" => "{4}{G}" } }

        def zone = :graveyard
        def exiles? = true
      end

      # CR 702.187a-c: mayhem, from the graveyard if you discarded the card this turn; without a cost, the card
      # may be played (a land too) for its usual costs.
      class Mayhem < AlternativeCost
        primitive :ability, :mayhem,
                  description: "Mayhem: as long as you discarded this card this turn, you may cast it from your " \
                               "graveyard by paying `cost` rather than its mana cost. Without `cost` (`\"mayhem\"`), " \
                               "you may play it from your graveyard (a land too) if you discarded it this turn. Cast " \
                               "option `via: \"alt:<ref>\"`.",
                  rules: %w[702.187a 702.187b 702.187c 118.9 601.2b 601.2f 601.2h 305.1],
                  params: { "cost" => "mana cost string, or a list of costs (optional)" },
                  example: { "mayhem" => { "cost" => "{1}{R}" } }

        def self.optional_cost? = true

        def zone = :graveyard
        def play = alternative? ? "cast" : "play"
        def functions?(engine, obj, _index) = obj.zone == zone && engine.discarded_this_turn?(obj)
      end

      # CR 702.185a-c: warp, from the hand. The permanent is exiled at the beginning of the next end step; its
      # owner may cast it from exile after this turn for as long as it remains exiled.
      class Warp < AlternativeCost
        primitive :ability, :warp,
                  description: "Warp: you may cast this card from your hand by paying `cost` rather than its mana " \
                               "cost. If you do, the permanent it becomes is exiled at the beginning of the next end " \
                               "step (a delayed triggered ability), and its owner may cast it from exile after this " \
                               "turn has ended for as long as it remains exiled (cast option `via: \"warped\"`). " \
                               "Conditions `{\"cast_with\": \"warp\"}` and `{\"cast_with_this_turn\": \"warp\"}` read it.",
                  rules: %w[702.185a 702.185b 702.185c 603.7 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "warp" => { "cost" => "{1}{R}" } }

        attr_reader :delayed

        def initialize(costs, path, errors)
          @delayed = Effects::WarpDelayed.build({}, errors, path)
          super
        end

        def try_effects = [delayed]
      end

      # CR 702.74a: evoke, from the hand; "When this permanent enters, if its evoke cost was paid, its controller
      # sacrifices it" is a linked triggered ability.
      class Evoke < AlternativeCost
        primitive :ability, :evoke,
                  description: "Evoke: you may cast this card by paying `cost` rather than its mana cost. When the " \
                               "permanent enters, if its evoke cost was paid, its controller sacrifices it (a triggered " \
                               "ability that comes with the keyword). Cast option `via: \"alt:<ref>\"`.",
                  rules: %w[702.74a 118.9 601.2b 601.2f 601.2h 603.4],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "evoke" => { "cost" => "{R/W}{R/W}" } }

        SACRIFICE = { "triggered" => { "when" => { "enters" => {} }, "if" => { "cast_with" => "evoke" },
                                       "effects" => [{ "sacrifice" => { "to" => "self" } }] } }.freeze

        attr_reader :linked_abilities

        def initialize(costs, path, errors)
          @linked_abilities = [Mechanics.build_entry(:ability, SACRIFICE, errors, "#{path}.sacrifice")].compact.freeze
          super
        end

        def allowed_types = %i[artifact creature enchantment planeswalker]
      end

      # CR 702.188a: web-slinging, paying `cost` and returning a tapped creature you control to its owner's hand.
      class WebSlinging < AlternativeCost
        primitive :ability, :web_slinging,
                  description: "Web-slinging: you may cast this spell by paying `cost` and returning a tapped creature " \
                               "you control to its owner's hand rather than its mana cost. The creature is a " \
                               "`choose_cost` decision, returned as the spell becomes cast. Cast option " \
                               "`via: \"alt:<ref>\"`.",
                  rules: %w[702.188a 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "web_slinging" => { "cost" => "{2}{G}" } }

        def returns = "tapped"
      end

      # CR 702.190a-b: sneak, during your declare blockers step at instant speed, paying `cost` and returning an
      # unblocked attacking creature you control to its owner's hand. A permanent spell enters tapped and
      # attacking whatever that creature was attacking.
      class Sneak < AlternativeCost
        primitive :ability, :sneak,
                  description: "Sneak: any time you could cast an instant during your declare blockers step, you may " \
                               "cast this spell by paying `cost` and returning an unblocked attacking creature you " \
                               "control to its owner's hand rather than its mana cost. A permanent spell cast this way " \
                               "enters tapped and attacking what that creature was attacking. Cast option " \
                               "`via: \"alt:<ref>\"`.",
                  rules: %w[702.190a 702.190b 506.3a 118.9 601.2b 601.2f 601.2h],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "sneak" => { "cost" => "{1}{B}" } }

        def returns = "unblocked"
        def instant_speed? = true

        def functions?(engine, obj, index)
          obj.zone == zone && engine.state.active == index && engine.state.step == :declare_blockers
        end
      end
    end

    module Effects
      # The delayed triggered ability of warp (CR 702.185a): "exile the permanent this spell becomes at the
      # beginning of the next end step". It is created as the spell becomes cast and watches the spell; the
      # permanent it became remembers the spell ("warp_spell"). Not a card-data primitive.
      class WarpDelayed < DelayedTrigger
        END_STEP = { "step_begins" => { "step" => "end", "whose" => "each" } }.freeze

        def self.keys = []

        def setup(_params, errors, path)
          @ref = "delayed:#{path}"
          trigger = Mechanics.build_entry(:trigger, END_STEP, errors, "#{path}.when")
          exile = WarpExile.build({ "to" => "watched" }, errors, "#{path}.exile")
          @delayed_ability = Abilities::TriggeredAbility.new(targets: [].freeze, effects: [exile].freeze, trigger: trigger)
        end

        def to_s = "at the beginning of the next end step, exile the permanent this spell became"
      end

      # Exiles the permanent a warped spell became; the card in exile is "warped" (CR 702.185b) and its owner
      # may cast it after this turn has ended (Engine::AltCasting#warped_methods).
      class WarpExile < Effect
        def self.keys = %w[to]

        def apply(engine, ctx)
          spells = refs(engine, ctx)
          engine.state.battlefield.dup.each do |id|
            next unless spells.include?(engine.object(id).memory["warp_spell"])

            fresh = engine.move!(id, :exile, reason: "warp")
            fresh.memory["warped"] = engine.state.turn if fresh&.zone == :exile
          end
        end

        def to_s = "exile the permanent this spell became"
      end
    end

    class Condition
      # How a spell was cast (CR 601.2a, 400.7d): `{"cast_with": "flashback"}` (cast using that keyword's
      # ability: "if its evoke cost was paid", "if this spell's mayhem cost was paid"), `{"cast_from":
      # "graveyard"}` ("if this spell was cast from a graveyard"; `{"not": {"cast_from": "hand"}}` is "from
      # anywhere other than your hand"), and `{"cast_with_this_turn": "warp"}` (any player cast a spell with
      # that keyword's cost this turn, CR 702.185c). The resolving spell, or the permanent it became (and
      # that permanent's triggered abilities), remembers it.
      class CastHow
        KEYS = %w[cast_with cast_from cast_with_this_turn].freeze
        KEYWORDS = %w[flashback harmonize mayhem warp evoke web_slinging sneak].freeze
        # Optional additional costs announced as the spell is cast (Engine::CastChoices#announce_kicker!):
        # "if this spell was cast using teamwork" (CR 702.194b).
        OPTIONAL = %w[teamwork].freeze
        ZONES = %w[hand graveyard exile library outside].freeze

        def self.build(key, data, errors, path)
          Mechanics.check_keys(data, [key], errors, path)
          value = data[key]
          allowed = { "cast_from" => ZONES, "cast_with" => KEYWORDS + OPTIONAL }.fetch(key, KEYWORDS)
          errors << "#{path}.#{key}: must be one of #{allowed.join(", ")}" unless allowed.include?(value)
          new(key, value)
        end

        def initialize(key, value)
          @key = key
          @value = value
          freeze
        end

        def true?(engine, ctx)
          return engine.cast_with_this_turn?(@value) if @key == "cast_with_this_turn"

          holder = engine.state.objects[ctx.object || ctx.source]
          return holder&.memory&.[]("kicked_with") == @value if OPTIONAL.include?(@value)

          holder&.memory&.[](@key) == @value
        end

        def to_s
          case @key
          when "cast_with" then OPTIONAL.include?(@value) ? "it was cast using #{@value}" : "its #{@value.tr("_", "-")} cost was paid"
          when "cast_from" then "it was cast from #{@value == "hand" ? "a hand" : "a #{@value}"}"
          else "a spell was cast with #{@value.tr("_", "-")} this turn"
          end
        end
      end
    end
  end
end
