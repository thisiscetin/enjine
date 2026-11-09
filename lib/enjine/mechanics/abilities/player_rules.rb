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
    #   cant_cast           the player can't cast spells (matching `spells`) (101.2, 601.3)
    #   cant_cast_except_from_hand  the player can't cast spells from anywhere other than their hand (601.3)
    #   spells_cant_be_countered    spells the player controls (matching `spells`) can't be countered (101.2, 701.6a)
    #   cant_gain_life      the player can't gain life (119.7)
    #   cant_activate       the player can't activate abilities of sources matching `filter`, except mana
    #                       abilities (602.5)
    #   protection_from_opponents  the player has protection from each of their opponents: opponents' spells
    #                       and abilities can't target them and damage from opponents' sources is prevented
    #                       (702.16b, 702.16e, 702.16k)
    #   damage_cant_be_prevented / combat_damage_cant_be_prevented  game rules: while any player has one, (combat)
    #                       damage can't be prevented (615.12)
    module PlayerRules
      RULES = {
        "hexproof" => %w[702.11c 115.4], "cant_attack" => %w[508.1c], "no_max_hand_size" => %w[402.2 514.1],
        "prevent_all_damage" => %w[615.1 615.1a], "cant_lose_for_life" => %w[704.5a 104.3b],
        "cant_sacrifice" => %w[701.21a 614.17b], "cant_cast" => %w[101.2 601.3],
        "cant_cast_except_from_hand" => %w[101.2 601.3], "spells_cant_be_countered" => %w[101.2 701.6a],
        "cant_gain_life" => %w[119.7], "cant_activate" => %w[101.2 602.5],
        "damage_cant_be_prevented" => %w[615.12], "combat_damage_cant_be_prevented" => %w[615.12],
        "protection_from_opponents" => %w[702.16b 702.16e 702.16k]
      }.freeze
      # Rules that take a `filter` of permanents (required for cant_sacrifice) or a card spec of `spells`.
      FILTERED = %w[cant_sacrifice cant_activate].freeze
      REQUIRED_FILTER = %w[cant_sacrifice].freeze
      SPELLS = %w[cant_cast spells_cant_be_countered].freeze

      def self.rule(params, errors, path)
        rule = Mechanics.fetch_param(params, :rule)
        errors << "#{path}.rule: must be one of #{RULES.keys.join(", ")}" unless RULES.key?(rule)
        rule
      end

      # [filter, spells] of a rule's data, validated for the rule.
      def self.qualifiers(params, rule, errors, path)
        raw = Mechanics.fetch_param(params, :filter)
        if raw.nil? && REQUIRED_FILTER.include?(rule)
          errors << "#{path}.filter: required"
        elsif raw && !FILTERED.include?(rule)
          errors << "#{path}.filter: only for #{FILTERED.join(", ")}"
        end
        spells = Mechanics.fetch_param(params, :spells)
        errors << "#{path}.spells: only for #{SPELLS.join(", ")}" if spells && !SPELLS.include?(rule)
        [raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.filter"), spells && CardSpec.build(spells, errors, "#{path}.spells")]
      end
    end

    module Abilities
      # A static ability giving players a rule: "You don't lose the game for having 0 or less life",
      # "You can't sacrifice Treasure tokens", "Your opponents can't attack", "Your opponents can't cast
      # spells during your turn", "Creature spells you control can't be countered", "Players can't gain life".
      class PlayerRule < Primitive
        AFFECTS = %w[you opponents each].freeze

        primitive :ability, :player_rule,
                  description: "While this permanent is on the battlefield (and its `if` condition holds), `rule` " \
                               "applies to the players in `affects` (you | opponents | each; default you). Rules: " \
                               "#{PlayerRules::RULES.keys.join(", ")}. `cant_sacrifice` takes a `filter` of the " \
                               "permanents that can't be sacrificed, `cant_activate` may take a `filter` of the " \
                               "sources whose abilities can't be activated (mana abilities still can), and " \
                               "`cant_cast` and `spells_cant_be_countered` may take a card spec of the `spells`. " \
                               "The damage rules apply to all damage whichever players they name.",
                  rules: PlayerRules::RULES.values.flatten.uniq + %w[604.1 604.2 611.3a],
                  params: { "rule" => PlayerRules::RULES.keys.join(" | "), "affects" => AFFECTS.join(" | "),
                            "filter" => "permanent filter (#{PlayerRules::FILTERED.join(", ")})",
                            "spells" => "card spec of the spells (#{PlayerRules::SPELLS.join(", ")})",
                            "if" => "condition (\"during your turn\": {\"your_turn\": true})" },
                  example: { "player_rule" => { "rule" => "cant_cast", "affects" => "opponents", "if" => { "your_turn" => true } } }

        attr_reader :rule, :affects, :filter, :spells, :condition

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[rule affects filter spells if], errors, path)
          rule = PlayerRules.rule(params, errors, path)
          affects = Mechanics.fetch_param(params, :affects) || "you"
          errors << "#{path}.affects: must be one of #{AFFECTS.join(", ")}" unless AFFECTS.include?(affects)
          filter, spells = PlayerRules.qualifiers(params, rule, errors, path)
          raw_if = Mechanics.fetch_param(params, :if)
          new(rule, affects, filter, spells: spells, condition: raw_if && Condition.build(raw_if, errors, "#{path}.if"))
        end

        def initialize(rule, affects, filter, spells: nil, condition: nil)
          super()
          @rule = rule
          @affects = affects
          @filter = filter
          @spells = spells
          @condition = condition
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

        # Its "as long as" / "during your turn" condition (CR 604.2), from its source's point of view.
        def active?(engine, source)
          condition.nil? || condition.true?(engine, EffectContext.new(source.controller, source.id, source.id, [], []))
        end

        # Whether the object asked about (a permanent for `filter`, a card for `spells`) is one the rule is about.
        def matches?(engine, object, source)
          (filter.nil? || filter.match?(engine, object.id, source.controller)) && (spells.nil? || spells.match?(engine, object))
        end

        def to_s
          who = { "you" => "you", "opponents" => "your opponents", "each" => "each player" }.fetch(affects)
          about = filter || spells
          "#{who}: #{rule.tr("_", " ")}#{" (#{about.is_a?(Class) ? about.primitive_name : about})" if about}" \
            "#{" as long as #{condition}" if condition}"
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
                               "#{(PlayerRules::RULES.keys - PlayerRules::REQUIRED_FILTER).join(", ")}.",
                  rules: PlayerRules::RULES.values.flatten.uniq + %w[611.2a 514.2],
                  params: { "rule" => (PlayerRules::RULES.keys - PlayerRules::REQUIRED_FILTER).join(" | "), "to" => "selector",
                            "duration" => DURATIONS.join(" | ") },
                  example: { "player_rule" => { "rule" => "no_max_hand_size", "duration" => "until_your_next_turn" } }

        attr_reader :rule, :duration

        def self.keys = %w[rule duration to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @rule = PlayerRules.rule(params, errors, path)
          errors << "#{path}.rule: #{@rule} needs a static ability (it takes a filter)" if PlayerRules::REQUIRED_FILTER.include?(@rule)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          errors << "#{path}.duration: must be one of #{DURATIONS.join(", ")}" unless DURATIONS.include?(@duration)
        end

        def apply(engine, ctx)
          affected = players(engine, ctx).map { Filters.player_ref(engine, it) }
          engine.add_continuous_effect!("player_rule", ctx, affected, "rule" => rule, "duration" => duration)
        end

        def to_s = "#{rule.tr("_", " ")} (#{duration.tr("_", " ")}) → #{to}"
      end
    end
  end
end
