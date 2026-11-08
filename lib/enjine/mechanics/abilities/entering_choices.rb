# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # Shared behaviour of "as this enters, choose ..." abilities (CR 614.12, 614.12a): the controller
      # chooses before the permanent enters (an enter_choice decision) and the permanent remembers the
      # choice in its memory, where linked abilities read it (CR 607.2).
      class EnteringChoice < Primitive
        def kind = :entering_choice
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
      end

      # "As this enters, choose a number between 0 and 10."
      class ChooseNumber < EnteringChoice
        primitive :ability, :choose_number,
                  description: "As this permanent enters, its controller chooses a number from `min` to `max`; abilities " \
                               "of it that say \"the chosen number\" use it.",
                  rules: %w[614.12 614.12a 607.2],
                  params: { "min" => "integer (default 0)", "max" => "integer" },
                  example: { "choose_number" => { "min" => 0, "max" => 10 } }

        attr_reader :min, :max

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[min max], errors, path)
          min = Mechanics.integer_param(params, :min, errors, path, default: 0, min: 0)
          max = Mechanics.integer_param(params, :max, errors, path, min: 0)
          errors << "#{path}.max: must be at least min" if max < min
          new(min, max)
        end

        def initialize(min, max)
          super()
          @min = min
          @max = max
          freeze
        end

        def to_s = "as this enters, choose a number from #{min} to #{max}"
        def options(_engine, _controller) = (min..max).map { { type: "number", number: it } }
        def enters_for(answer) = { "memory" => { "chosen_number" => answer[:number] } }
      end

      # "As this enters, choose a nonland card name." The names offered are those of the cards in the game's
      # decklists (CR 201.4: a player chooses a card name; names of cards outside the game can't matter).
      class ChooseCardName < EnteringChoice
        primitive :ability, :choose_card_name,
                  description: "As this permanent enters, its controller chooses a card name among the cards in the " \
                               "game (`not`: card types the named card mustn't have, e.g. [\"land\"]); abilities of it " \
                               "that say \"the chosen name\" use it.",
                  rules: %w[614.12 614.12a 201.4 201.4a 607.2],
                  params: { "not" => "list of card types" },
                  example: { "choose_card_name" => { "not" => ["land"] } }

        attr_reader :excluded

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[not], errors, path)
          excluded = Mechanics.fetch_param(params, :not) || []
          types = Filters::Restricted::TYPES
          unless excluded.is_a?(Array) && (excluded - types).empty?
            errors << "#{path}.not: must be a list of card types (#{types.join(", ")})"
            excluded = []
          end
          new(excluded.map(&:to_sym))
        end

        def initialize(excluded)
          super()
          @excluded = excluded.freeze
          freeze
        end

        def to_s = "as this enters, choose a #{excluded.map { "non#{it}" }.join(" ")} card name".squeeze(" ")

        def options(engine, _controller)
          names = engine.state.decklists.flatten.uniq.filter_map do |card|
            defn = engine.catalog.fetch(card)
            defn.name unless defn.types.intersect?(excluded)
          end
          names.uniq.sort.map { { type: "name", name: it } }
        end

        def enters_for(answer) = { "memory" => { "chosen_name" => answer[:name] } }
      end

      # "This land enters tapped unless you control two or more other lands." A self-replacement effect that
      # checks its condition as the permanent would enter (CR 614.1c, 614.12): it isn't on the battlefield
      # yet, so "you control" counts only the others.
      class EntersTappedUnless < Primitive
        primitive :ability, :enters_tapped_unless,
                  description: "This permanent enters tapped unless `condition` is true as it would enter (checked for " \
                               "its controller; the permanent itself isn't on the battlefield yet).",
                  rules: %w[614.1c 614.12],
                  params: { "condition" => "a condition, e.g. {\"controls\": {\"each\": \"land\", \"controller\": \"you\"}, " \
                                           "\"at_least\": 2}" },
                  example: { "enters_tapped_unless" => { "condition" => { "controls" => { "each" => "land", "controller" => "you" },
                                                                          "at_least" => 2 } } }

        attr_reader :condition

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[condition], errors, path)
          raw = Mechanics.fetch_param(params, :condition)
          condition = raw.nil? ? ((errors << "#{path}.condition: required") && nil) : Condition.build(raw, errors, "#{path}.condition")
          new(condition)
        end

        def initialize(condition)
          super()
          @condition = condition
          freeze
        end

        def kind = :enters_tapped
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "enters tapped unless #{condition}"

        # Called by the replacement pass for the entering object (Replacements.entering!).
        def modify_entering_for(engine, controller, object_id, enters)
          enters["tapped"] = true unless condition&.true?(engine, EffectContext.new(controller, object_id, nil, []))
        end
      end
    end
  end
end
