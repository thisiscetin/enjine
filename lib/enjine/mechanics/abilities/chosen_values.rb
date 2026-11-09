# frozen_string_literal: true

require_relative "entering_choices"

module Enjine
  module Mechanics
    # "Choose a color", "choose a creature type", "choose a card type" and "choose Khans or Dragons"
    # (CR 105.4, 205.3m, 205.2a, 607.2d, 607.2f). The choice is remembered in an object's memory under a
    # `chosen_*` key, where filters ("of the chosen type", Filters::Restricted), conditions ({"chosen": word})
    # and linked abilities read it (CR 607.2d). Made as a permanent enters (an ability, CR 614.12) or while
    # a spell or ability resolves (an effect, remembered on the resolving object).
    module Chosen
      # What is chosen -> [memory key, option key].
      MEMORY = { "color" => "chosen_color", "creature_type" => "chosen_type", "card_type" => "chosen_card_type",
                 "option" => "chosen_option" }.freeze
      # CR 105.4: one of the five colors.
      COLORS = %w[W U B R G].freeze
      # CR 205.2a: the card types of traditional Magic cards.
      CARD_TYPES = %w[artifact battle creature enchantment instant kindred land planeswalker sorcery].freeze
      WORD = /\A[a-z][a-z0-9_]*\z/

      # The values a player may choose: every color, creature type (CR 205.3m) or card type, or the named options.
      def self.values(kind, words)
        case kind
        when "color" then COLORS
        when "creature_type" then Keywords::Changeling::CREATURE_TYPES.map(&:to_s)
        when "card_type" then CARD_TYPES
        else words
        end
      end

      # `"options": ["khans", "dragons"]` for "option": two or more lowercase words (CR 607.2f).
      def self.words(kind, params, errors, path)
        return [].freeze unless kind == "option"

        list = Mechanics.fetch_param(params, :options)
        ok = list.is_a?(Array) && list.size >= 2 && list.all? { WORD.match?(it.to_s) } && list.uniq.size == list.size
        errors << "#{path}.options: must list two or more different lowercase words" unless ok
        ok ? list.map(&:to_s).freeze : [].freeze
      end

      def self.memory(kind, value) = { MEMORY.fetch(kind) => value }
      def self.words_text(kind, words) = kind == "option" ? words.join(" or ") : "a #{kind.tr("_", " ")}"
    end

    module Abilities
      # "As this enters, choose a color / creature type / card type / one of the words" (CR 614.12, 607.2d).
      class EnteringChosen < EnteringChoice
        def self.kind_name = raise(NotImplementedError)

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, kind_name == "option" ? %w[options] : [], errors, path)
          new(Chosen.words(kind_name, params, errors, path))
        end

        def initialize(words)
          super()
          @words = words
          freeze
        end

        def to_s = "as this enters, choose #{Chosen.words_text(self.class.kind_name, @words)}"

        def options(_engine, _controller)
          kind = self.class.kind_name
          Chosen.values(kind, @words).map { { type: kind, kind.to_sym => it } }
        end

        def enters_for(answer) = { "memory" => Chosen.memory(self.class.kind_name, answer[self.class.kind_name.to_sym]) }
      end

      # "As this enters, choose a color."
      class ChooseColor < EnteringChosen
        primitive :ability, :choose_color,
                  description: "As this permanent enters, its controller chooses a color; filters with \"colors\": " \
                               "\"chosen\" (and other abilities of it) use it.",
                  rules: %w[614.12 105.4 607.2d], example: { "choose_color" => {} }
        def self.kind_name = "color"
      end

      # "As this enters, choose a creature type."
      class ChooseCreatureType < EnteringChosen
        primitive :ability, :choose_creature_type,
                  description: "As this permanent enters, its controller chooses a creature type; filters with " \
                               "\"subtypes\": \"chosen\" use it.",
                  rules: %w[614.12 205.3m 607.2d], example: { "choose_creature_type" => {} }
        def self.kind_name = "creature_type"
      end

      # "As this enters, choose a card type."
      class ChooseCardType < EnteringChosen
        primitive :ability, :choose_card_type,
                  description: "As this permanent enters, its controller chooses a card type; filters with \"types\": " \
                               "\"chosen\" (or \"not\": \"chosen\") use it.",
                  rules: %w[614.12 205.2a 607.2d], example: { "choose_card_type" => {} }
        def self.kind_name = "card_type"
      end

      # "As this enters, choose Khans or Dragons." Abilities of it check the word with {"chosen": word}.
      class ChooseOption < EnteringChosen
        primitive :ability, :choose_option,
                  description: "As this permanent enters, its controller chooses one of the `options` (words with no " \
                               "rules meaning); a condition {\"chosen\": word} is true when that word was chosen.",
                  rules: %w[614.12 607.2f 614.12b],
                  params: { "options" => "list of two or more lowercase words" },
                  example: { "choose_option" => { "options" => %w[khans dragons] } }
        def self.kind_name = "option"
      end
    end

    module Effects
      # "Choose a creature type." while resolving: the choice is remembered on the resolving spell or
      # ability, so its later effects' filters ("of the chosen type") and conditions read it (CR 607.2d).
      class ResolvingChosen < ChoiceEffect
        def self.kind_name = raise(NotImplementedError)
        def self.default_to = "you"
        def self.keys = kind_name == "option" ? %w[options to if] : %w[to if]

        def setup(params, errors, path) = @words = Chosen.words(self.class.kind_name, params, errors, path)

        def to_s = "choose #{Chosen.words_text(self.class.kind_name, @words)}"

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || condition.nil? || condition.true?(engine, ctx)

          kind = self.class.kind_name
          answer = answers(locals).first
          unless answer
            chooser = players(engine, ctx).first || ctx.controller
            return ask(engine, locals, chooser, "Choose #{Chosen.words_text(kind, @words)}",
                       Chosen.values(kind, @words).map { { "type" => kind, kind => it } })
          end
          engine.state.objects[ctx.object]&.memory&.merge!(Chosen.memory(kind, answer[kind]))
          :done
        end
      end

      # "Choose a color."
      class ChooseColorEffect < ResolvingChosen
        primitive :effect, :choose_color,
                  description: "The player (`to`, default you) chooses a color; later effects of this spell or ability " \
                               "read it with \"colors\": \"chosen\".",
                  rules: %w[105.4 607.2d 608.2c], params: { "to" => "player selector (default you)" },
                  example: { "choose_color" => {} }
        def self.kind_name = "color"
      end

      # "Choose a creature type."
      class ChooseCreatureTypeEffect < ResolvingChosen
        primitive :effect, :choose_creature_type,
                  description: "The player (`to`, default you) chooses a creature type; later effects of this spell or " \
                               "ability read it with \"subtypes\": \"chosen\".",
                  rules: %w[205.3m 607.2d 608.2c], params: { "to" => "player selector (default you)" },
                  example: { "choose_creature_type" => {} }
        def self.kind_name = "creature_type"
      end

      # "Choose a card type."
      class ChooseCardTypeEffect < ResolvingChosen
        primitive :effect, :choose_card_type,
                  description: "The player (`to`, default you) chooses a card type; later effects of this spell or " \
                               "ability read it with \"types\": \"chosen\".",
                  rules: %w[205.2a 607.2d 608.2c], params: { "to" => "player selector (default you)" },
                  example: { "choose_card_type" => {} }
        def self.kind_name = "card_type"
      end

      # "Choose odd or even." Later effects check the word with {"if": {"chosen": word}}.
      class ChooseOptionEffect < ResolvingChosen
        primitive :effect, :choose_option,
                  description: "The player (`to`, default you) chooses one of the `options` (words); later effects of this " \
                               "spell or ability check it with the condition {\"chosen\": word}.",
                  rules: %w[607.2f 608.2c],
                  params: { "options" => "list of two or more lowercase words", "to" => "player selector (default you)" },
                  example: { "choose_option" => { "options" => %w[odd even] } }
        def self.kind_name = "option"
      end
    end

    class Condition
      # {"chosen": "khans"}: that word was chosen for this object (CR 607.2f), by its "as this enters"
      # choice or earlier while this spell or ability resolved.
      class ChosenIs
        def self.build(data, errors, path)
          Mechanics.check_keys(data, %w[chosen], errors, path)
          errors << "#{path}.chosen: must be a lowercase word" unless Chosen::WORD.match?(data["chosen"].to_s)
          new(data["chosen"].to_s)
        end

        def initialize(word)
          @word = word
          freeze
        end

        def true?(engine, ctx) = Filters.chosen_memory(engine, ctx.source, ctx)["chosen_option"] == @word
        def to_s = "#{@word} was chosen"
      end
    end
  end
end
