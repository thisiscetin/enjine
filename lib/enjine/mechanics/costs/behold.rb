# frozen_string_literal: true

module Enjine
  module Mechanics
    # Behold (CR 701.4a): "behold a [quality]" means reveal a [quality] card from your hand or choose a
    # [quality] permanent you control. Whether a [quality] was beheld looks at the object as it was beheld
    # (CR 701.4b).
    module Beholding
      # The cards in `index`'s hand and the permanents they control matching the card spec.
      def self.candidates(engine, index, spec)
        perms = engine.state.battlefield.select { engine.object(it).controller == index }
        (perms + engine.player(index).hand).select { spec.match?(engine, engine.object(it)) }
      end

      # Reveals a card from the hand (CR 701.4a); the entry remembers what was beheld (CR 701.4b).
      def self.behold!(engine, index, id)
        obj = engine.object(id)
        engine.reveal!(index, [id]) if obj.zone == :hand
        facts = engine.chars(obj)
        { "object" => id, "zone" => obj.zone.to_s, "types" => facts.types.map(&:to_s),
          "subtypes" => facts.subtypes.map(&:to_s) }
      end
    end

    module Costs
      # "Behold a Goblin" / "Behold three Elementals" / "Behold a Kithkin and exile it" as a cost (CR 701.4a,
      # 601.2h). Each choice is a card in your hand or a permanent you control matching `card`; with `exile`
      # they are exiled as the spell or ability becomes cast, linked to it ("the exiled card", CR 607.2a). A
      # spell's linked cards stay linked to the permanent it becomes.
      class Behold < Choosing
        primitive :cost, :behold,
                  description: "Behold `count` (default 1) objects matching the card spec `card`: each a card " \
                               "revealed from your hand or a permanent you control, chosen while casting or " \
                               "activating. `exile: true` also exiles them as it becomes cast; they are then " \
                               "\"exiled with\" it (selector `exiled_with`).",
                  rules: %w[701.4a 701.4b 601.2h 602.2b 118.3 607.2a],
                  params: { "card" => "card spec (required), e.g. {\"subtypes\": [\"goblin\"]}",
                            "count" => "integer (default 1)", "exile" => "true: exile what was beheld" },
                  example: { "behold" => { "card" => { "subtypes" => ["goblin"] }, "exile" => true } }

        def self.keys = %w[card count exile]

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          count = Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1)
          raw = Mechanics.fetch_param(params, :card)
          errors << "#{path}.card: required" if raw.nil?
          new(CardSpec.build(raw, errors, "#{path}.card"), count, false, params, errors, path)
        end

        def initialize(filter, count, other, params, errors, path)
          @exile = Mechanics.flag_param(params, :exile, errors, path)
          super
        end

        # Not the card being cast (it is on the stack once casting begins).
        def candidates(engine, object) = Beholding.candidates(engine, object.controller, filter) - [object.id]
        def choose!(engine, option) = Beholding.behold!(engine, engine.object(option[:object]).controller, option[:object])

        def pay_chosen!(engine, object, entries)
          return unless @exile

          entries.each do |entry|
            card = engine.state.objects[entry["object"]]
            next unless card&.zone.to_s == entry["zone"]

            fresh = engine.move!(card.id, :exile, reason: "cost")
            engine.link_exiled!(object.id, fresh.id) if fresh
          end
        end

        def to_s = "Behold #{count == 1 ? "a" : count} #{filter.to_s.delete_suffix(" card")}#{" and exile it" if @exile}"
      end
    end
  end
end
