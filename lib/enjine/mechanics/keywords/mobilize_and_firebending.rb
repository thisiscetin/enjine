# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # A keyword ability with a number that stands for a triggered ability written in the card DSL
      # ("Mobilize 2", "Firebending X"). Its `amount` is any amount; it's written into the generated
      # effects, which validate it.
      class NumberedTrigger < TriggeredAbility
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[amount], errors, path)
          amount = Mechanics.fetch_param(params, :amount)
          errors << "#{path}.amount: required" if amount.nil?
          data = expansion(amount || 0)
          trigger = Mechanics.build_entry(:trigger, data["when"], errors, "#{path}.when")
          body = parse_body(data.except("when"), errors, path)
          new(**body, effects: (body[:effects] + extra_effects).freeze, trigger: trigger, amount: amount)
        end

        # Effects the keyword adds after its printed ones (none by default).
        def self.extra_effects = []

        def initialize(amount: nil, **)
          @amount = amount
          super(**)
        end

        def to_s = "#{self.class.primitive_name.to_s.tr("_", " ").capitalize} #{@amount.is_a?(Integer) ? @amount : "X"}"
      end

      # Mobilize N (CR 702.181a): "Whenever this creature attacks, create N 1/1 red Warrior creature tokens.
      # Those tokens enter tapped and attacking. Sacrifice them at the beginning of the next end step."
      class Mobilize < NumberedTrigger
        primitive :ability, :mobilize,
                  description: "Mobilize `amount`: whenever this creature attacks, create that many 1/1 red Warrior " \
                               "creature tokens tapped and attacking; sacrifice them at the beginning of the next end step.",
                  rules: %w[702.181a 508.4],
                  params: { "amount" => "amount" },
                  example: { "mobilize" => { "amount" => 2 } }

        WARRIOR = { "name" => "Warrior", "types" => ["creature"], "subtypes" => ["warrior"], "colors" => ["R"], "power" => 1,
                    "toughness" => 1 }.freeze

        def self.expansion(amount)
          { "when" => { "attacks" => {} },
            "effects" => [{ "create_token" => { "token" => WARRIOR, "amount" => amount, "tapped" => true, "attacking" => true } },
                          { "delayed_trigger" => { "when" => { "step_begins" => { "step" => "end", "whose" => "each" } },
                                                   "effects" => [{ "sacrifice" => { "to" => { "result" => 0 } } }] } }] }
        end
      end

      # Firebending N (CR 702.189a): "Whenever this creature attacks, add N {R}. Until end of combat, you
      # don't lose this mana as steps and phases end."
      class Firebending < NumberedTrigger
        primitive :ability, :firebending,
                  description: "Firebending `amount`: whenever this creature attacks, add that much {R}; you don't " \
                               "lose this mana as steps end until end of combat.",
                  rules: %w[702.189a 500.5],
                  params: { "amount" => "amount" },
                  example: { "firebending" => { "amount" => 2 } }

        def self.expansion(amount)
          { "when" => { "attacks" => {} },
            "effects" => [{ "add_mana" => { "produce" => "{R}", "amount" => amount, "until" => "end_of_combat" } }] }
        end

        # CR 702.189b: the ability resolving is firebending ("whenever you firebend").
        def self.extra_effects = @extra_effects ||= [Effects::Firebent.new(to: nil, params: {}, errors: [], path: "firebending")].freeze
      end
    end

    module Effects
      # The last step of a firebending ability: it has resolved, so its controller firebended (CR 702.189b).
      class Firebent < Effect
        def self.keys = []
        def to_s = "(you firebend)"

        def apply(engine, ctx)
          engine.emit Events::KeywordAction.new(player: engine.name(ctx.controller), action: "firebend", amount: nil)
        end
      end
    end
  end
end
