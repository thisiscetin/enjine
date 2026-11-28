# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # Collect evidence N (CR 701.59a): "exile any number of cards from your graveyard with total mana value N or
      # greater" (CR 202.3), never the card the spell or ability belongs to. The player chooses cards one at a time
      # (`choose_cost`) and may stop (`done`) once they total N; the cards are exiled as the spell becomes cast
      # (CR 601.2h). It can't be paid without enough mana value in the graveyard (CR 701.59b, 118.3). As an
      # optional additional cost (`additional_cost` with `optional: true`), "if evidence was collected" is
      # `{"cast_with": "additional_cost"}`; inside `pay` (and so ward) it is "you may collect evidence N. If you do".
      class CollectEvidence < CardsCost
        primitive :cost, :collect_evidence,
                  description: "Collect evidence `N`: exile any number of other cards from your graveyard with total " \
                               "mana value N or greater, chosen one at a time (`choose_cost`; `done` once they total " \
                               "N). Not payable without that much mana value in your graveyard. \"If evidence was " \
                               "collected\": make it an optional `additional_cost` and read `{\"cast_with\": " \
                               "\"additional_cost\"}`.",
                  rules: %w[701.59a 701.59b 701.59c 202.3 601.2h 118.3],
                  params: { "(value)" => "integer >= 1: N" },
                  example: { "collect_evidence" => 6 }

        attr_reader :evidence

        def self.scalar_params? = true
        def self.zone = :graveyard

        def self.build(params, errors, path, **)
          errors << "#{path}: must be an integer >= 1" unless params.is_a?(Integer) && params.positive?
          new(nil, "any", false, { "evidence" => params.is_a?(Integer) ? params : 1 }, errors, path)
        end

        def initialize(filter, count, other, params, errors, path)
          @evidence = params["evidence"]
          super(filter, count, other, {}, errors, path)
        end

        # CardsCost's "any number" check reads `symbols`; collect evidence reads mana value instead.
        def symbols_param(_raw, _errors, _path) = { "evidence" => true }

        def mana_value_among(engine, ids) = ids.sum { engine.chars(it).mana_cost&.mana_value.to_i }

        def payable?(engine, object) = mana_value_among(engine, candidates(engine, object)) >= evidence

        # Each chosen card remembers its mana value, so the total is known without the engine.
        def choose!(engine, option) = { "object" => option[:object], "mana_value" => mana_value_among(engine, [option[:object]]) }

        # Engine::CastChoices: `done` is offered once the chosen cards total N; with nothing left to choose it's done.
        def finishable?(entries) = entries.sum { it["mana_value"].to_i } >= evidence

        def chosen?(engine, object, entries, done)
          finishable?(entries) && (done || choice_options(engine, object, entries).empty?)
        end

        def cards_text = "cards with total mana value #{evidence} or greater"
        def to_s = "Collect evidence #{evidence}"
      end
    end
  end
end
