# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # "Get five poison counters" as a cost (CR 118.1, 122.1): the payer gets that many counters of a kind
      # (a player with ten or more poison counters loses the game, CR 704.5c). It can always be paid.
      class GetCounters < Primitive
        primitive :cost, :get_counters,
                  description: "You get `amount` counters of the kind `counter` (e.g. poison). It can always be paid.",
                  rules: %w[118.1 122.1 704.5c],
                  params: { "counter" => "player counter kind, e.g. \"poison\"", "amount" => "integer >= 1" },
                  example: { "get_counters" => { "counter" => "poison", "amount" => 5 } }

        attr_reader :counter, :amount

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[counter amount], errors, path)
          counter = Mechanics.fetch_param(params, :counter)
          errors << "#{path}.counter: must be a counter kind, e.g. \"poison\"" unless counter.is_a?(String) && !counter.empty?
          new(counter.to_s, Mechanics.integer_param(params, :amount, errors, path, min: 1))
        end

        def initialize(counter, amount)
          super()
          @counter = counter
          @amount = amount
          freeze
        end

        def mana? = false
        def spell_cost? = true
        def payable?(_engine, _object) = true
        def pay!(engine, object) = engine.add_player_counters!(object.controller, counter, amount)
        def to_s = "Get #{amount} #{counter} counter#{"s" unless amount == 1}"
      end
    end
  end
end
