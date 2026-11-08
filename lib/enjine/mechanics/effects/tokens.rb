# frozen_string_literal: true

require "digest"

module Enjine
  module Mechanics
    module Effects
      # Create token permanents (CR 111.1, 701.7).
      class CreateToken < Effect
        primitive :effect, :create_token,
                  description: "Create `amount` tokens under the referenced player's control (default: you). `token` is " \
                               "a predefined token name (Treasure, Clue, Food) or an inline card definition. " \
                               "`tapped: true` creates them tapped.",
                  rules: %w[111.1 111.10 701.7a 704.5d],
                  params: { "token" => "\"Treasure\" | \"Clue\" | \"Food\" | {card data}", "amount" => "integer (default 1)",
                            "tapped" => "boolean", "to" => "selector (default \"you\")" },
                  example: { "create_token" => { "token" => { "name" => "Soldier", "types" => ["creature"],
                                                              "subtypes" => ["soldier"], "power" => 1, "toughness" => 1 } } }

        attr_reader :definition, :tapped

        def self.keys = %w[token amount tapped to if]
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :token)
          data = raw.is_a?(String) ? Enjine::Tokens.fetch(raw) : raw
          @tapped = Mechanics.fetch_param(params, :tapped) == true
          unless data.is_a?(Hash)
            errors << "#{path}.token: must be a predefined token (#{Enjine::Tokens::LIBRARY.keys.join(", ")}) or card data"
            return
          end
          @definition = CardDefinition.token(data)
        rescue InvalidCardDefinition => e
          e.errors.each { errors << "#{path}.token.#{it}" }
        end

        def apply(engine, ctx)
          return unless definition

          n = amount_for(engine, ctx)
          players(engine, ctx).each { |index| n.times { engine.create_token!(definition, index, tapped: tapped) } }
        end

        def to_s = "create #{amount} #{definition&.name} token#{"s" if amount != 1}#{" tapped" if tapped} → #{to}"
      end
    end
  end
end
