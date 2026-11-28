# frozen_string_literal: true

require_relative "alternative_costs"
require_relative "cards_have"
require_relative "../abilities/play_permissions"

module Enjine
  module Mechanics
    module Triggers
      # Miracle's trigger event (CR 702.94a): "When you reveal this card this way". It never matches an event by
      # itself; Abilities::Miracle.watch! queues it as the card is drawn. Not a card-data primitive.
      class MiracleRevealed < Trigger
        def self.keys = []
        def watches?(_event) = false
        def to_s = "When you reveal this card as the first card you drew this turn"
      end
    end

    module Effects
      # Miracle's triggered ability's effect (CR 702.94a): "you may cast it by paying [cost] rather than its mana
      # cost", now, while the trigger resolves (CR 608.2g), and only if the revealed card is still in its owner's
      # hand. The revealed card and the cast method are in the trigger's memory ("miracle"). Not a card-data
      # primitive.
      class MiracleCast < CastFree
        def self.keys = []

        def prompt = "Miracle: you may cast it by paying its miracle cost"
        def to_s = "you may cast it by paying its miracle cost"

        private

        def candidates(engine, ctx, locals)
          info = Selector.memory(engine, ctx)["miracle"] or return []
          id = info["object"]
          obj = engine.state.objects[id]
          return [] unless obj&.zone == :hand && obj.owner == ctx.controller && !locals.fetch("declined", []).include?(id)

          locals["via"] = info["via"]
          Abilities::Miracle.casting(obj) do
            method = engine.play_methods(ctx.controller, obj).find { it["via"] == info["via"] }
            method && engine.castable_via?(ctx.controller, obj, method) ? [{ "type" => "cast", "object" => id }] : []
          end
        end

        def start_cast!(engine, index, id, locals)
          locals["casting"] = id
          Abilities::Miracle.casting(engine.object(id)) { engine.begin_cast!(index, id, via: locals["via"]) }
          :wait
        end
      end
    end

    module Abilities
      # Miracle [cost] (CR 702.94a-b): "You may reveal this card from your hand as you draw it if it's the first card
      # you've drawn this turn. When you reveal this card this way, you may cast it by paying [cost] rather than its
      # mana cost." As the card is drawn as its owner's first card this turn, the triggered ability (which comes with
      # the keyword) is put on the stack the next time a player would receive priority; as it resolves, its owner
      # may cast the card if it's still in their hand (an `effect_choice`: cast or done), paying the miracle cost,
      # whatever its timing. The reveal itself is made for them (the trigger shows the card). A permanent can give
      # cards in your hand miracle (`cards_have` with `zone: "hand"`). `{"cast_with": "miracle"}` reads it.
      class Miracle < AlternativeCost
        primitive :ability, :miracle,
                  description: "Miracle `cost`: when you draw this card as the first card you drew this turn, it's " \
                               "revealed and a triggered ability lets you cast it as that ability resolves by paying " \
                               "`cost` rather than its mana cost (an `effect_choice`: cast or done), if it's still in " \
                               "your hand. Never offered at priority. `cards_have` with `zone: \"hand\"` can give it to " \
                               "cards in your hand.",
                  rules: %w[702.94a 702.94b 608.2g 118.9 601.2b 601.2f 601.2h 121.2],
                  params: { "cost" => "mana cost string, or a list of costs" },
                  example: { "miracle" => { "cost" => "{1}{R}" } }

        CASTING = "miracle_cast"

        attr_reader :linked_abilities

        def initialize(costs, path, errors)
          effect = Effects::MiracleCast.build({}, errors, "#{path}.cast")
          trigger = Triggers::MiracleRevealed.new({}, errors, "#{path}.revealed")
          @linked_abilities = [TriggeredAbility.new(trigger: trigger, targets: [].freeze, effects: [effect].freeze,
                                                    zone: :hand)].freeze
          super
        end

        # The cast method works only for the card its trigger is casting (Miracle.casting); never at priority.
        def usable?(_engine, obj, _index) = obj.memory[CASTING] == true
        # Cast while its trigger resolves: timing doesn't apply (CR 608.2g).
        def instant_speed? = true

        # Cast while its trigger resolves: nobody gets priority until that resolution is over (CR 608.2g).
        def method_for(ref, **)
          method = super
          method&.merge("resolving" => true)
        end

        # Marks the card as being cast for its miracle cost while the block runs.
        def self.casting(obj)
          obj.memory[CASTING] = true
          yield
        ensure
          obj.memory.delete(CASTING)
        end

        # CR 702.94a: a card drawn as its owner's first card this turn, with miracle (its own, or given by a
        # permanent they control, CR 611.3a), triggers. Called for every event (Engine::Triggering#watch_triggers!).
        def self.watch!(engine, event)
          return unless event.is_a?(Events::ZoneChanged) && event.reason == "draw" && event.to == "hand"

          obj = engine.state.objects[event.new_id] or return
          return unless engine.turn_log(obj.owner)["drawn"].to_i == 1

          miracles(engine, obj).each do |source, via|
            memory = { "miracle" => { "object" => obj.id, "via" => via } }
            engine.queue_pending_trigger!(source, event, memory)
          end
        end

        # [[trigger source, cast method via]] for each miracle ability `obj` has: its own (the trigger is the card's
        # linked ability) and those permanents give it (the granting ability's linked trigger, on its card).
        def self.miracles(engine, obj)
          own = engine.chars(obj).abilities.filter_map do |inst|
            next unless inst.ability.is_a?(Miracle)

            [{ "id" => obj.id, "card" => obj.card, "controller" => obj.owner, "ability" => "#{inst.ref}:linked:0" },
             "alt:#{inst.ref}"]
          end
          own + granted(engine, obj)
        end

        def self.granted(engine, obj)
          engine.board_abilities(:cards_have).filter_map do |perm, grant|
            next unless grant.granted.is_a?(Miracle) && perm.controller == obj.owner && grant.zone == :hand &&
                        grant.cards.match?(engine, obj)

            inst = engine.chars(perm).abilities.find { it.ability.equal?(grant) }
            [{ "id" => obj.id, "card" => perm.card, "controller" => obj.owner, "ability" => "#{inst.ref}:linked:0" },
             "alt:#{Engine::AltCasting::GRANTED}#{perm.id}:#{inst.ref}"]
          end
        end
      end
    end
  end
end
