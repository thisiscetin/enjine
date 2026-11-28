# frozen_string_literal: true

require_relative "../costs/sacrifice"
require_relative "../effects/return_to_battlefield"

module Enjine
  module Mechanics
    module Costs
      # Craft's "Exile this permanent" (CR 702.167a): exiles it like `exile_self`, and the craft ability being
      # activated remembers the card in exile ("crafted"), which its effect returns transformed.
      class CraftSelf < ExileSelf
        INSTANCE = new.freeze

        def pay!(engine, object)
          fresh = super or return nil
          holder = engine.casting && engine.state.objects[engine.casting["object"]]
          holder.memory["crafted"] = fresh.id if holder && fresh.zone == :exile
          fresh
        end
      end

      # Craft's materials (CR 702.167a-b): "Exile [materials] from among permanents you control and/or cards in
      # your graveyard", never the crafting permanent. `count` of them matching the card spec `card`, or with
      # `or_more` that many or more (`done` once enough are chosen). Each is chosen while activating
      # (`choose_cost`) and exiled as the ability becomes activated; the ability remembers them ("exiled_for_cost").
      class CraftMaterials < CardsCost
        ZONES = %i[battlefield graveyard].freeze

        def self.zone = :graveyard

        def self.from(data, errors, path)
          data = {} unless data.is_a?(Hash)
          Mechanics.check_keys(data, %w[card count or_more], errors, path)
          count = Mechanics.integer_param(data, :count, errors, path, default: 1, min: 1)
          raw = Mechanics.fetch_param(data, :card)
          spec = raw && CardSpec.build(raw, errors, "#{path}.card")
          new(spec, count, Mechanics.flag_param(data, :or_more, errors, path), {}, errors, path)
        end

        def or_more? = @other

        # A permanent you control (a token too) or a card in your graveyard, other than the crafting permanent.
        def candidates(engine, object)
          pl = engine.player(object.controller)
          graveyard = pl.graveyard.select { |id| filter.nil? || filter.match?(engine, engine.object(id)) }
          permanents = engine.state.battlefield.select do |id|
            id != object.id && engine.object(id).controller == object.controller &&
              (filter.nil? || filter.chars_match?(engine, engine.chars(id)))
          end
          permanents + graveyard
        end

        def choices_needed = or_more? ? 0 : count
        def payable?(engine, object) = candidates(engine, object).size >= count
        def finishable?(entries) = or_more? && entries.size >= count

        def chosen?(engine, object, entries, done)
          return entries.size >= count unless or_more?

          finishable?(entries) && (done || choice_options(engine, object, entries).empty?)
        end

        # As it becomes activated, the chosen materials still on the battlefield or in the graveyard are exiled.
        def pay_chosen!(engine, _object, entries)
          entries.map { it["object"] }.select { ZONES.include?(engine.state.objects[it]&.zone) }.each { pay_card!(engine, it) }
        end

        def to_s
          many = or_more? ? "#{count} or more" : { 1 => "a" }.fetch(count, count)
          "Exile #{many} #{filter || "card"}#{"s" unless count == 1} from among permanents you control and/or cards in your graveyard"
        end
      end
    end

    module Effects
      # Craft's effect (CR 702.167a): "Return this card to the battlefield transformed under its owner's control" —
      # the card the craft ability exiled as its cost (Costs::CraftSelf). Not a card-data primitive.
      class CraftReturn < ReturnToBattlefield
        def self.keys = []

        def refs(engine, ctx)
          id = engine.state.objects[ctx.object]&.memory&.[]("crafted")
          id && engine.state.exile.include?(id) ? [id] : []
        end

        def to_s = "return this card to the battlefield transformed"
      end
    end

    module Abilities
      # Craft with [materials] [cost] (CR 702.167a-c): "[Cost], Exile this permanent, Exile [materials] from among
      # permanents you control and/or cards in your graveyard: Return this card to the battlefield transformed under
      # its owner's control. Activate only as a sorcery." A double-faced card's front face has it; a card that
      # isn't double-faced stays in exile (CR 712.11a, Effects::ReturnToBattlefield).
      class Craft < ActivatedAbility
        primitive :ability, :craft,
                  description: "Craft with `materials` `cost`: pay `cost`, exile this permanent and exile the " \
                               "materials (`count` (default 1) permanents you control and/or cards in your graveyard " \
                               "matching the card spec `card`; `or_more: true`: that many or more), chosen with " \
                               "`choose_cost`: return this card to the battlefield transformed under its owner's " \
                               "control. Sorcery speed. The exiled materials are the selector \"exiled_for_cost\".",
                  rules: %w[702.167a 702.167b 702.167c 712.11a 602.2b 406.1],
                  params: { "cost" => "mana cost string, or a list of costs",
                            "materials" => "{\"card\": card spec, \"count\": n, \"or_more\": true}" },
                  example: { "craft" => { "cost" => "{3}{W}", "materials" => { "card" => { "types" => ["artifact"] } } } }

        attr_reader :materials

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[cost materials], errors, path)
          raw = Mechanics.fetch_param(params, :cost)
          paid = case raw
                 when String then [Costs::ManaPayment.build(raw, errors, "#{path}.cost")]
                 when Array then StackAbility.parse_costs({ "cost" => raw }, errors, path)
                 else (errors << "#{path}.cost: must be a mana cost string or a list of costs") && []
                 end
          materials = Costs::CraftMaterials.from(Mechanics.fetch_param(params, :materials), errors, "#{path}.materials")
          effect = Effects::CraftReturn.new(to: nil, params: { "transformed" => true }, errors: errors, path: "#{path}.return")
          new(targets: [].freeze, effects: [effect].freeze, costs: (paid + [Costs::CraftSelf::INSTANCE, materials]).freeze,
              sorcery: true, materials: materials)
        end

        def initialize(materials:, **)
          @materials = materials
          super(**)
        end

        def to_s = "Craft — #{costs.join(", ")}: return this card to the battlefield transformed"
      end
    end
  end
end
