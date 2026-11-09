# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # One-shot and continuous effects (CR 609-611). Each effect is built from data
      # and applied at resolution with an EffectContext.
      # Base effect: parses the common "to" selector, an "amount" (fixed or computed, see
      # Mechanics::Amount) and an optional "if" condition checked on resolution (CR 608.2c).
      class Effect < Primitive
        attr_reader :to, :condition

        def self.keys = %w[amount to if]
        def self.default_to = nil

        # `results_count`: how many earlier effects of the enclosing list a {"result": n} selector may name.
        def self.build(params, errors, path, targets_count: 0, results_count: 0, **)
          Mechanics.check_keys(params, keys, errors, path)
          raw_to = Mechanics.fetch_param(params, :to) || default_to
          to = if raw_to.nil?
                 errors << "#{path}.to: required"
                 nil
               else
                 Selector.build(raw_to, errors, "#{path}.to", targets_count: targets_count, results_count: results_count)
               end
          new(to: to, params: params, errors: errors, path: path, targets_count: targets_count, results_count: results_count)
        end

        def initialize(to:, params:, errors:, path:, targets_count: 0, results_count: 0)
          super()
          @to = to
          @targets_count = targets_count
          @results_count = results_count
          if self.class.keys.include?("amount")
            raw = Mechanics.fetch_param(params, :amount)
            @amount = if raw.nil?
                        (errors << "#{path}.amount: required") && Amount::Fixed.new(0)
                      else
                        Amount.build(raw, errors, "#{path}.amount", targets_count: targets_count,
                                                                    results_count: results_count)
                      end
          end
          raw_if = Mechanics.fetch_param(params, :if)
          @condition = raw_if && Condition.build(raw_if, errors, "#{path}.if", targets_count: targets_count,
                                                                               results_count: results_count)
          setup(params, errors, path)
          freeze
        end

        # The fixed amount (for display), or the amount computed for this resolution.
        def amount = @amount.is_a?(Amount::Fixed) ? @amount.n : @amount
        def amount_for(engine, ctx) = @amount.value(engine, ctx)

        def setup(_params, _errors, _path) = nil

        # Effects nested inside this one (a "may" or delayed trigger's list); see CardDefinition#all_effects.
        def nested_effects = []

        # CR 118.3: whether the effect can be done fully now (an optional effect offered as a cost).
        def possible?(_engine, _ctx) = true

        # Runs the effect during resolution. Effects that need a player's choice override this,
        # keep their progress in `locals` (plain JSON data) and return :wait after asking.
        def run(engine, ctx, _locals)
          apply(engine, ctx) if condition.nil? || condition.true?(engine, ctx)
          :done
        end

        def refs(engine, ctx) = to ? to.resolve(engine, ctx) : []

        def to_s
          words = self.class.primitive_name.tr("_", " ")
          words += " #{amount}" if amount
          "#{words} → #{to}"
        end

        def objects(engine, ctx)
          refs(engine, ctx).select { engine.state.objects.key?(it) && engine.state.battlefield.include?(it) }
        end

        def players(engine, ctx) = refs(engine, ctx).filter_map { Filters.player_index(engine, it) }
      end

      # Moves each referenced permanent, or card in one of the class's other zones (a target card in a
      # graveyard, a card chosen from a hand), to a zone. A card that has left the zone it was in
      # (CR 400.7, 608.2b) isn't found any more, so it isn't moved.
      class ZoneEffect < Effect
        def self.keys = %w[to if]
        def self.zone = raise(NotImplementedError)
        def self.reason = name.split("::").last.downcase
        def self.from_zones = %i[battlefield graveyard]

        def apply(engine, ctx)
          movable(engine, ctx).each { move(engine, ctx, it) }
        end

        # The referenced objects that are permanents or cards in the zones this effect moves cards from.
        def movable(engine, ctx)
          refs(engine, ctx).select do |id|
            obj = engine.state.objects[id]
            obj && !obj.ability? && self.class.from_zones.include?(obj.zone)
          end
        end

        def move(engine, ctx, id)
          Linked.remember!(engine, ctx, id)
          engine.move!(id, self.class.zone, reason: self.class.reason)
        end
      end

      # Base for effects that ask the controller (or a referenced player) questions while resolving.
      # Progress lives in `locals` (plain data in the resolve frame), so they survive export/import.
      class ChoiceEffect < Effect
        def ask(engine, locals, player, prompt, choices)
          locals["asked"] = true
          engine.ask!("kind" => "effect_choice", "player" => player, "prompt" => prompt, "choices" => choices)
          :wait
        end

        def answers(locals) = locals["answers"] ||= []
      end

      # Runs a nested effect list one effect at a time (`may`, `pay`, `choose_cards`); a waiting effect keeps its locals
      # under "child", where Engine#effect_answer! delivers answers.
      module NestedList
        def run_list(engine, ctx, locals, list)
          while locals["next"] < list.size
            return :wait if list[locals["next"]].run(engine, ctx, locals["child"] ||= {}) == :wait

            locals.delete("child")
            locals["next"] += 1
          end
          :done
        end

        def parse_lists(params, errors, path, keys)
          keys.to_h do |key|
            [key, Abilities::StackAbility.parse_effects(params, errors, path, @targets_count, key: key.to_sym,
                                                                                              results_count: @results_count)]
          end.freeze
        end
      end
    end
  end
end
