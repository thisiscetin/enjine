# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # Ninjutsu's "Reveal this card from your hand" (CR 702.49a-b): every player sees the card. Activating an ability of
      # a card in a hand already reveals it (Engine::Casting#begin_activation!, CR 602.2a), so paying adds nothing. It
      # functions only from the hand.
      class RevealSelf < Primitive
        INSTANCE = new.freeze

        def mana? = false
        def zone = :hand
        def payable?(engine, object) = engine.player(object.owner).hand.include?(object.id)
        def pay!(_engine, _object) = nil
        def to_s = "Reveal this card from your hand"
      end

      # Ninjutsu's "Return an unblocked attacking creature you control to its owner's hand" (CR 702.49a). An
      # unblocked creature exists only once blockers are declared (CR 509.1h), so only from the declare blockers step
      # to the end of combat. The paid entry remembers what it was attacking (CR 702.49c).
      class ReturnUnblockedAttacker < Choosing
        STEPS = %i[declare_blockers combat_damage end_of_combat].freeze

        def self.instance = @instance ||= new(nil, 1, false, {}, [], "")

        def candidates(engine, object)
          return [] unless STEPS.include?(engine.state.step)

          engine.attackers.filter_map do |id, attack|
            perm = engine.state.objects[id]
            id if perm && !attack["blocked"] && perm.controller == object.controller && engine.chars(perm).creature?
          end
        end

        def choose!(engine, option) = { "object" => option[:object], "attacking" => engine.attackers.dig(option[:object], "target") }

        def pay_chosen!(engine, _object, entries)
          entries.each do |entry|
            perm = engine.state.objects[entry["object"]]
            engine.move!(perm.id, :hand, reason: "ninjutsu") if perm&.zone == :battlefield
          end
        end

        def what = "unblocked attacking creature you control"
        def to_s = "Return an unblocked attacking creature you control to its owner's hand"
      end
    end

    module Effects
      # Ninjutsu's effect (CR 702.49a, 702.49c): "Put this card onto the battlefield from your hand tapped and
      # attacking", attacking the player, planeswalker or battle the returned creature was attacking. It isn't cast.
      # Nothing happens if the card has left its owner's hand.
      class NinjutsuEnter < Effect
        def self.keys = %w[to]

        def apply(engine, ctx)
          card = engine.state.objects[ctx.source]
          return unless card && card.zone == :hand

          target = Array(engine.state.objects[ctx.object]&.paid).find { it.key?("attacking") }&.fetch("attacking")
          enters = { "tapped" => true }
          enters["attacking"] = target if target && (target.start_with?("player:") || engine.state.battlefield.include?(target))
          engine.move!(card.id, :battlefield, reason: "ninjutsu", controller: card.owner, enters: enters)
        end

        def to_s = "put this card onto the battlefield from your hand tapped and attacking"
      end
    end

    module Abilities
      # Ninjutsu (CR 702.49a): "[Cost], Reveal this card from your hand, Return an unblocked attacking creature you
      # control to its owner's hand: Put this card onto the battlefield from your hand tapped and attacking." An
      # activated ability of the card in the hand (not a cast, unlike sneak, CR 702.190): it can't be countered as a
      # spell, cast triggers don't see it, and it can be activated any time you have priority once blockers are
      # declared (the declare blockers, combat damage and end of combat steps).
      class Ninjutsu < ActivatedAbility
        primitive :ability, :ninjutsu,
                  description: "Ninjutsu: an activated ability from your hand: pay `cost`, reveal this card and return an " \
                               "unblocked attacking creature you control to its owner's hand (a `choose_cost` decision) to " \
                               "put this card onto the battlefield tapped and attacking what that creature was attacking. " \
                               "It isn't cast. Usable while you have an unblocked attacker (after blockers are declared).",
                  rules: %w[702.49a 702.49b 702.49c 509.1h 506.3a 113.6m 602.2a],
                  params: { "cost" => "mana cost string, e.g. \"{1}{U}{B}\"" },
                  example: { "ninjutsu" => { "cost" => "{1}{U}" } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          mana = raw.nil? ? ((errors << "#{path}.cost: required") && "{0}") : raw
          costs = [Costs::ManaPayment.build(mana, errors, "#{path}.cost"), Costs::RevealSelf::INSTANCE,
                   Costs::ReturnUnblockedAttacker.instance].freeze
          effect = Effects::NinjutsuEnter.new(to: Selector.new(:self), params: {}, errors: errors, path: path)
          new(targets: [].freeze, effects: [effect].freeze, costs: costs, sorcery: false, zone: :hand)
        end

        def to_s = "Ninjutsu #{costs.first}"
      end
    end
  end
end
