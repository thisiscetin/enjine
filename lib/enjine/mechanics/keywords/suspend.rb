# frozen_string_literal: true

require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Keywords
      # Suspend (CR 702.62a-b): a card that has suspend and is exiled with time counters is "suspended". At the
      # beginning of its owner's upkeep they remove a time counter from it; when the last is removed, if it's
      # exiled, they may play it without paying its mana cost, and a creature spell cast this way has haste
      # while they control it. Both triggered abilities are the engine's (#watch!), put on the stack as this
      # keyword's ability "keyword:suspend", so they work for a card that gained suspend ("exile it with four
      # time counters; if it doesn't have suspend, it gains suspend", Effects::Suspend) as for a printed one.
      class Suspend < Primitive
        primitive :keyword, :suspend,
                  description: "This card has suspend: while it's exiled with time counters, its owner removes one at " \
                               "the beginning of each of their upkeeps; when the last is removed they may play it without " \
                               "paying its mana cost (a creature spell gains haste). \"Suspend N—cost\" is the ability " \
                               "`suspend`.",
                  rules: %w[702.62a 702.62b], example: { "keywords" => ["suspend"] }

        REF = "keyword:suspend"

        # Never triggers by itself (zone :rules): the engine queues it (#watch!).
        class Rules
          def watches?(_event) = false
          def leaves_battlefield? = false
          def to_s = "Suspend"
        end

        def self.intrinsic_abilities
          @intrinsic_abilities ||= [
            Abilities::TriggeredAbility.new(trigger: Rules.new.freeze, targets: [].freeze, zone: :rules,
                                            effects: [Effects::SuspendStep.new].freeze)
          ].freeze
        end

        # The card has suspend: printed, from "Suspend N—cost", or gained in exile (memory "suspend").
        def self.has?(engine, obj)
          return true if obj.memory["suspend"]

          chars = engine.chars(obj)
          chars.keyword?(:suspend) || chars.abilities.any? { it.ability.is_a?(Abilities::Suspend) }
        end

        # CR 702.62b.
        def self.suspended?(engine, obj) = obj.zone == :exile && obj.counters["time"].to_i.positive? && has?(engine, obj)

        # Queues the upkeep trigger of each suspended card of the active player, and the "last counter removed"
        # trigger of an exiled card with suspend.
        def self.watch!(engine, event)
          case event
          when Events::StepBegan
            return unless event.step == "upkeep"

            engine.state.exile.each do |id|
              obj = engine.object(id)
              queue!(engine, obj, event, "upkeep") if obj.owner == engine.state.active && suspended?(engine, obj)
            end
          when Events::CountersChanged
            return unless event.counter == "time" && event.to.zero? && event.from.positive?

            obj = engine.state.objects[event.object]
            queue!(engine, obj, event, "last") if obj&.zone == :exile && has?(engine, obj)
          end
        end

        # CR 108.4a: the ability of a card in exile is controlled by its owner.
        def self.queue!(engine, obj, event, step)
          engine.queue_pending_trigger!({ "id" => obj.id, "card" => obj.card, "controller" => obj.owner, "ability" => REF },
                                        event, { "suspend" => step })
        end
      end
    end

    module Abilities
      # "Suspend N—[cost]" (CR 702.62a, 116.2f): if you could begin to cast this card from your hand, you may pay
      # `cost` and exile it with N time counters (a special action, `{type: "special_action"}`). The card has
      # suspend (Keywords::Suspend).
      class Suspend < Primitive
        primitive :ability, :suspend,
                  description: "Suspend `amount`—`cost`: whenever you could begin to cast this card from your hand, you " \
                               "may pay `cost` and exile it with `amount` time counters (special action " \
                               "`{type: \"special_action\"}`); then it works as the keyword `suspend`.",
                  rules: %w[702.62a 702.62c 116.2f],
                  params: { "amount" => "integer >= 1 (time counters)", "cost" => "mana cost string" },
                  example: { "suspend" => { "amount" => 3, "cost" => "{2}{W}" } }

        attr_reader :amount, :special_cost

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[amount cost], errors, path)
          amount = Mechanics.integer_param(params, :amount, errors, path, min: 1)
          cost = Costs::ManaPayment.build(Mechanics.fetch_param(params, :cost).to_s, errors, "#{path}.cost").mana_cost
          new(amount, cost)
        end

        def initialize(amount, cost)
          super()
          @amount = amount
          @special_cost = cost
          freeze
        end

        def kind = :suspend
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "Suspend #{amount}—#{special_cost}"

        # CR 702.62a, 702.62c: when you could begin to cast it from your hand (timing; nothing forbids it).
        def special_allowed?(engine, obj, index)
          chars = engine.chars(obj)
          obj.zone == :hand && (chars.type?(:instant) || chars.keyword?(:flash) || engine.sorcery_timing?(index)) &&
            !engine.cast_forbidden?(index, obj)
        end

        def special!(engine, obj, _index) = Effects::Suspend.exile!(engine, obj.id, amount)
      end
    end

    module Effects
      # "Exile [it] with N time counters on it. If it doesn't have suspend, it gains suspend." (CR 702.62a-b)
      class Suspend < Effect
        primitive :effect, :suspend,
                  description: "Exile each referenced card or spell with `amount` time counters on it; if it doesn't " \
                               "have suspend, it gains suspend (keyword `suspend`) while it stays exiled.",
                  rules: %w[702.62a 702.62b 406.1],
                  params: { "amount" => "amount (time counters)", "to" => "selector (a spell, a card or a permanent)" },
                  example: { "suspend" => { "to" => { "triggering" => "object" }, "amount" => 4 } }

        def self.keys = %w[amount to if]

        def self.exile!(engine, id, amount)
          fresh = engine.move!(id, :exile, reason: "suspend")
          return unless fresh&.zone == :exile

          fresh.memory["suspend"] = true
          engine.add_counters!(fresh, "time", amount, by_player: fresh.owner)
        end

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          refs(engine, ctx).each do |id|
            obj = engine.state.objects[id]
            Suspend.exile!(engine, id, n) if obj && !obj.ability? && obj.zone != :exile
          end
        end

        def to_s = "exile with #{amount} time counters (suspend) → #{to}"
      end

      # The resolving suspend trigger (Keywords::Suspend): "upkeep" removes a time counter if the card is still
      # suspended (CR 603.4); "last" lets its owner play it free if it's still exiled. A creature spell cast this
      # way has haste while they control it (memory "haste_while_controlled_by").
      class SuspendStep < CastFree
        def self.keys = []

        def initialize
          errors = []
          super(to: Selector.build("self", errors, "keyword:suspend", targets_count: 0), params: { "play" => true },
                errors: errors, path: "keyword:suspend")
        end

        def run(engine, ctx, locals)
          card = engine.state.objects[ctx.source]
          return :done unless card&.zone == :exile || locals["asked"] || locals["casting"]

          if Selector.memory(engine, ctx)["suspend"] == "upkeep"
            engine.remove_counters!(card, "time", 1) if Keywords::Suspend.suspended?(engine, card)
            return :done
          end
          super
        end

        def to_s = "remove a time counter; when the last is removed, you may play it without paying its mana cost"

        private

        def settle_cast!(engine, locals)
          id = locals["casting"]
          super
          return if id.nil? || engine.state.objects.key?(id) || engine.state.stack.empty?

          spell = engine.object(engine.state.stack.first)
          spell.memory["haste_while_controlled_by"] = spell.controller if engine.chars(spell).creature?
        end
      end
    end
  end
end
