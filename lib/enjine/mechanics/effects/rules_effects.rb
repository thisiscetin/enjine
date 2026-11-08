# frozen_string_literal: true

module Enjine
  module Mechanics
    # Rules that apply to a player rather than to an object (see Engine::Rules#player_rule?):
    #   hexproof            the player can't be the target of spells or abilities opponents control (702.11c)
    #   cant_attack         the player can't declare attackers (508.1c)
    #   no_max_hand_size    the player has no maximum hand size (402.2, 514.1)
    #   prevent_all_damage  all damage that would be dealt to the player is prevented (615.1)
    #   cant_lose_for_life  the player doesn't lose the game for having 0 or less life (704.5a, 104.3b)
    #   cant_sacrifice      the player can't sacrifice permanents matching `filter` (701.21a, 614.17b)
    module PlayerRules
      RULES = {
        "hexproof" => %w[702.11c 115.4], "cant_attack" => %w[508.1c], "no_max_hand_size" => %w[402.2 514.1],
        "prevent_all_damage" => %w[615.1 615.1a], "cant_lose_for_life" => %w[704.5a 104.3b],
        "cant_sacrifice" => %w[701.21a 614.17b]
      }.freeze
      FILTERED = %w[cant_sacrifice].freeze

      def self.rule(params, errors, path)
        rule = Mechanics.fetch_param(params, :rule)
        errors << "#{path}.rule: must be one of #{RULES.keys.join(", ")}" unless RULES.key?(rule)
        rule
      end
    end

    module Abilities
      # A static ability giving players a rule: "You don't lose the game for having 0 or less life",
      # "You can't sacrifice Treasure tokens", "Your opponents can't attack".
      class PlayerRule < Primitive
        AFFECTS = %w[you opponents each].freeze

        primitive :ability, :player_rule,
                  description: "While this permanent is on the battlefield, `rule` applies to the players in " \
                               "`affects` (you | opponents | each; default you). Rules: " \
                               "#{PlayerRules::RULES.keys.join(", ")}. `cant_sacrifice` takes a `filter` of the " \
                               "permanents that can't be sacrificed.",
                  rules: PlayerRules::RULES.values.flatten.uniq + %w[604.1 611.3a],
                  params: { "rule" => PlayerRules::RULES.keys.join(" | "), "affects" => AFFECTS.join(" | "),
                            "filter" => "permanent filter (cant_sacrifice only)" },
                  example: { "player_rule" => { "rule" => "cant_sacrifice",
                                                "filter" => { "permanent" => { "token" => true, "subtypes" => ["treasure"] } } } }

        attr_reader :rule, :affects, :filter

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[rule affects filter], errors, path)
          rule = PlayerRules.rule(params, errors, path)
          affects = Mechanics.fetch_param(params, :affects) || "you"
          errors << "#{path}.affects: must be one of #{AFFECTS.join(", ")}" unless AFFECTS.include?(affects)
          raw = Mechanics.fetch_param(params, :filter)
          filtered = PlayerRules::FILTERED.include?(rule)
          errors << "#{path}.filter: #{filtered ? "required" : "only for #{PlayerRules::FILTERED.join(", ")}"}" if filtered == raw.nil?
          new(rule, affects, raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.filter"))
        end

        def initialize(rule, affects, filter)
          super()
          @rule = rule
          @affects = affects
          @filter = filter
          freeze
        end

        def kind = :player_rule
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # Whether the rule applies to player `index` for a source controlled by `controller`.
        def applies_to?(index, controller)
          affects == "each" || (affects == "you") == (index == controller)
        end

        def matches?(engine, object, source) = filter.nil? || filter.match?(engine, object.id, source.controller)

        def to_s
          who = { "you" => "you", "opponents" => "your opponents", "each" => "each player" }.fetch(affects)
          "#{who}: #{rule.tr("_", " ")}#{" (#{filter.is_a?(Class) ? filter.primitive_name : filter})" if filter}"
        end
      end
    end

    module Effects
      # "You gain hexproof until end of turn", "Prevent all damage that would be dealt to you this turn",
      # "You have no maximum hand size until your next turn", "They can't attack this turn".
      class PlayerRuleEffect < Effect
        DURATIONS = %w[end_of_turn until_your_next_turn].freeze

        primitive :effect, :player_rule,
                  description: "Each referenced player (default you) gets `rule` for the `duration`: end_of_turn " \
                               "(default) or until_your_next_turn (until the controller's next turn begins). Rules: " \
                               "#{(PlayerRules::RULES.keys - PlayerRules::FILTERED).join(", ")}.",
                  rules: PlayerRules::RULES.values.flatten.uniq + %w[611.2a 514.2],
                  params: { "rule" => (PlayerRules::RULES.keys - PlayerRules::FILTERED).join(" | "), "to" => "selector",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "player_rule" => { "rule" => "no_max_hand_size", "duration" => "until_your_next_turn" } }

        attr_reader :rule, :duration

        def self.keys = %w[rule duration to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @rule = PlayerRules.rule(params, errors, path)
          errors << "#{path}.rule: #{@rule} needs a static ability (it takes a filter)" if PlayerRules::FILTERED.include?(@rule)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          affected = players(engine, ctx).map { Filters.player_ref(engine, it) }
          engine.add_continuous_effect!("player_rule", ctx, affected, "rule" => rule, "duration" => duration)
        end

        def to_s = "#{rule.tr("_", " ")} (#{duration.tr("_", " ")}) → #{to}"
      end

      # Base for effects that may end the game: once it's over, nothing else in the list happens.
      class GameEndEffect < Effect
        def self.keys = %w[to if]
        def self.default_to = "you"

        def run(engine, ctx, locals)
          super
          engine.state.over? ? :wait : :done # the game ended: resolution stops here
        end
      end

      # "You win the game." (CR 104.2b)
      class WinGame < GameEndEffect
        primitive :effect, :win_game,
                  description: "Each referenced player (default you) wins the game: every opponent loses it.",
                  rules: %w[104.2a 104.2b 104.3f],
                  params: { "to" => "selector" },
                  example: "win_game"

        def apply(engine, ctx) = players(engine, ctx).each { engine.win_game!(it) }
        def to_s = "win the game → #{to}"
      end

      # "You lose the game." (CR 104.3e)
      class LoseGame < GameEndEffect
        primitive :effect, :lose_game,
                  description: "Each referenced player (default you) loses the game.",
                  rules: %w[104.3e 104.4a],
                  params: { "to" => "selector" },
                  example: "lose_game"

        def apply(engine, ctx) = players(engine, ctx).each { engine.lose_game!(it) }
        def to_s = "lose the game → #{to}"
      end

      # "Take an extra turn after this one." (CR 500.7)
      class ExtraTurn < Effect
        primitive :effect, :extra_turn,
                  description: "Each referenced player (default you) takes an extra turn after this one. Extra " \
                               "turns are taken most recently created first.",
                  rules: %w[500.7],
                  params: { "to" => "selector" },
                  example: { "extra_turn" => { "if" => { "began_extra_turn" => false } } }

        def self.keys = %w[to if]
        def self.default_to = "you"

        def apply(engine, ctx) = players(engine, ctx).each { engine.add_extra_turn!(it) }
        def to_s = "take an extra turn after this one → #{to}"
      end
    end

    class Condition
      # "If you haven't begun an extra turn this game" (CR 500.7): {"began_extra_turn": false}.
      class BeganExtraTurn
        def initialize(wanted)
          @wanted = wanted
          freeze
        end

        def true?(engine, ctx) = engine.began_extra_turn?(ctx.controller) == @wanted
        def to_s = @wanted ? "you've begun an extra turn this game" : "you haven't begun an extra turn this game"
      end
    end
  end
end
