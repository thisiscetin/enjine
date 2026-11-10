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
      # "As this artifact enters, look at an opponent's hand, then choose any card name" (`look_at_hand`).
      class ChooseCardName < EnteringChoice
        primitive :ability, :choose_card_name,
                  description: "As this permanent enters, its controller chooses a card name among the cards in the " \
                               "game (`not`: card types the named card mustn't have, e.g. [\"land\"]; `types`: it must " \
                               "have one of these, [\"land\"] for \"a land card name\"); abilities of it that say \"the " \
                               "chosen name\" use it. `look_at_hand: \"opponent\"`: first they look at an opponent's hand.",
                  rules: %w[614.12 614.12a 201.4 201.4a 607.2 701.20e],
                  params: { "not" => "list of card types", "types" => "list of card types",
                            "look_at_hand" => "\"opponent\"" },
                  example: { "choose_card_name" => { "not" => ["land"] } }

        attr_reader :excluded, :types

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[not types look_at_hand], errors, path)
          look = Mechanics.fetch_param(params, :look_at_hand)
          errors << "#{path}.look_at_hand: must be \"opponent\"" unless [nil, "opponent"].include?(look)
          new(type_list(params, :not, errors, path), type_list(params, :types, errors, path), look: !look.nil?)
        end

        def self.type_list(params, key, errors, path)
          list = Mechanics.fetch_param(params, key) || []
          known = Filters::Restricted::TYPES
          return list.map(&:to_sym) if list.is_a?(Array) && (list - known).empty?

          errors << "#{path}.#{key}: must be a list of card types (#{known.join(", ")})"
          []
        end

        # The names of the cards in the game matching the type restrictions, sorted.
        def self.names(engine, types, excluded)
          engine.state.decklists.flatten.uniq.filter_map do |card|
            defn = engine.catalog.fetch(card)
            defn.name if !defn.types.intersect?(excluded) && (types.empty? || defn.types.intersect?(types))
          end.uniq.sort
        end

        def initialize(excluded, types = [], look: false)
          super()
          @excluded = excluded.freeze
          @types = types.freeze
          @look = look
          freeze
        end

        def to_s
          "as this enters, #{"look at an opponent's hand, then " if @look}choose a " \
          "#{(excluded.map { "non#{it}" } + types).join(" ")} card name".squeeze(" ")
        end

        # CR 701.20e: looking at an opponent's hand comes before the choice.
        def before_choice(engine, controller)
          engine.look_at!(controller, engine.state.opponent(controller), engine.player(engine.state.opponent(controller)).hand) if @look
        end

        def options(engine, _controller) = ChooseCardName.names(engine, types, excluded).map { { type: "name", name: it } }
        def enters_for(answer) = { "memory" => { "chosen_name" => answer[:name] } }
      end
    end
  end
end
