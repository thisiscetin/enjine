# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Exile a card from your hand" / "Exile two cards from your hand" as a cost (CR 406.1, 601.2h,
      # 602.2b). The cards are chosen while casting or activating and exiled as it becomes cast; never the
      # card the ability belongs to.
      class ExileFromHand < Choosing
        primitive :cost, :exile_from_hand,
                  description: "Exile `count` cards from your hand (default 1), chosen while casting or activating, " \
                               "exiled as the spell or ability becomes cast. `card` (a card spec) restricts which.",
                  rules: %w[406.1 601.2h 602.2b 118.3],
                  params: { "count" => "integer (default 1)", "card" => "card spec, e.g. {\"types\": [\"creature\"]}" },
                  example: { "exile_from_hand" => { "count" => 1 } }

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[count card], errors, path)
          count = Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1)
          raw = Mechanics.fetch_param(params, :card)
          spec = raw && CardSpec.build(raw, errors, "#{path}.card")
          new(spec, count, false, params, errors, path)
        end

        def candidates(engine, object)
          engine.player(object.controller).hand.select do |id|
            id != object.id && (filter.nil? || filter.match?(engine, engine.object(id)))
          end
        end

        def pay_chosen!(engine, _object, entries)
          entries.each { engine.move!(it["object"], :exile, reason: "cost") if engine.state.objects[it["object"]]&.zone == :hand }
        end

        def to_s = "Exile #{count == 1 ? "a" : count} #{filter || "card"}#{"s" if count > 1} from your hand"
      end
    end
  end
end
