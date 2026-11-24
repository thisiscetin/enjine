# frozen_string_literal: true

require "digest"

module Enjine
  module Mechanics
    module Effects
      # Create token permanents (CR 111.1, 701.7).
      class CreateToken < ChoiceEffect
        primitive :effect, :create_token,
                  description: "Create `amount` tokens under the referenced player's control (default: you). `token` is " \
                               "a predefined token name (Treasure, Clue, Food) or an inline card definition. " \
                               "`tapped: true` creates them tapped; `attacking: true` attacking (only for the attacking " \
                               "player during combat, CR 506.3b); when the defending player controls a planeswalker, " \
                               "the controller chooses for each token whether it attacks that player or one of their " \
                               "planeswalkers (CR 508.4). `size` (an amount, fixed as the effect starts) makes them N/N " \
                               "(\"an X/X Spirit token, where X is ...\"; part of their copiable values).",
                  rules: %w[111.1 111.10 701.7a 704.5d 508.4 506.3b 707.2],
                  params: { "token" => "\"Treasure\" | \"Clue\" | \"Food\" | {card data}", "amount" => "integer (default 1)",
                            "tapped" => "boolean", "attacking" => "boolean", "to" => "selector (default \"you\")",
                            "size" => "amount: the tokens are N/N" },
                  example: { "create_token" => { "token" => { "name" => "Soldier", "types" => ["creature"],
                                                              "subtypes" => ["soldier"], "power" => 1, "toughness" => 1 } } }

        attr_reader :definition, :tapped, :attacking

        def self.keys = %w[token amount tapped attacking size to if]
        ATTACK_STEPS = %i[declare_attackers declare_blockers combat_damage end_of_combat].freeze
        def self.default_to = "you"

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          params = params.transform_keys(&:to_s)
          params["amount"] = 1 unless params.key?("amount")
          super
        end

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :token)
          data = raw.is_a?(String) ? Enjine::Tokens.fetch(raw) : raw
          @tapped = Mechanics.fetch_param(params, :tapped) == true
          @attacking = Mechanics.fetch_param(params, :attacking) == true
          raw_size = Mechanics.fetch_param(params, :size)
          @size = raw_size && Amount.build(raw_size, errors, "#{path}.size", targets_count: @targets_count,
                                                                             results_count: @results_count)
          unless data.is_a?(Hash)
            errors << "#{path}.token: must be a predefined token (#{Enjine::Tokens::LIBRARY.keys.join(", ")}) or card data"
            return
          end
          @definition = CardDefinition.token(data)
        rescue InvalidCardDefinition => e
          e.errors.each { errors << "#{path}.token.#{it}" }
        end

        # CR 614.12a: an "as this enters" choice of each token is made (one token at a time) before any is
        # created; the number and players are fixed as the effect starts.
        def run(engine, ctx, locals)
          return :done unless definition && (locals.key?("tokens") || condition.nil? || condition.true?(engine, ctx))

          unless locals.key?("tokens")
            n = amount_for(engine, ctx)
            locals["size"] = [@size.value(engine, ctx), 0].max if @size
          end
          entries = locals["tokens"] ||= players(engine, ctx).flat_map do |index|
            Array.new(n) { [engine.token_key(definition, "#{index}.#{it}"), index] }
          end
          return :wait if engine.ask_entering_choices!(locals, entries) == :wait
          return :wait if ask_attack_targets(engine, locals, entries) == :wait

          entries.each do |key, index|
            enters = engine.with_entering_answer(locals, key, index, nil)
            enters = (enters || {}).merge("attacking" => locals.dig("attacks", key) || true) if attacks?(engine, index)
            engine.create_token!(definition, index, tapped: tapped, enters: enters, memory: size_memory(locals))
          end
          :done
        end

        def to_s
          "create #{amount} #{"#{@size}/#{@size} " if @size}#{definition&.name} token#{"s" if amount != 1}" \
            "#{" tapped" if tapped}#{" attacking" if attacking} → #{to}"
        end

        # An N/N token: N is part of its copiable values (Engine::Copies, "copy_except"; CR 707.2).
        def size_memory(locals)
          n = locals["size"] or return nil
          { "copy_except" => { "power" => n, "toughness" => n } }
        end

        # CR 508.4, 506.3b: tokens enter attacking only under the attacking player's control, in combat.
        def attacks?(engine, index) = attacking && engine.state.active == index && ATTACK_STEPS.include?(engine.state.step)

        # CR 508.4: for each token entering attacking, its controller chooses the defending player or a planeswalker
        # they control, before any is created (kept in locals["attacks"], token key => target).
        def ask_attack_targets(engine, locals, entries)
          targets = engine.attack_targets
          return if targets.size < 2

          keys = entries.select { |_, index| attacks?(engine, index) }.map(&:first)
          locals["attacks"] = keys.zip(answers(locals).map { it["target"] }).to_h.compact
          entry = entries.find { |key, _| keys.include?(key) && !locals["attacks"].key?(key) }
          return unless entry

          ask(engine, locals, entry[1], "Choose what the #{definition.name} token attacks",
              targets.map { { "type" => "attack", "target" => it } })
        end
      end
    end
  end
end
