# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # "Your speed increases by 1" (CR 702.179c-d): a player without speed gets that much; never above 4.
      class IncreaseSpeed < Effect
        def self.keys = %w[to]
        def apply(engine, ctx) = engine.increase_speed!(ctx.controller, 1)
        def to_s = "your speed increases by 1"
      end
    end

    module Keywords
      # Start your engines! (CR 702.179a, 704.5aa): a player who controls a permanent with it and has no speed
      # gets speed 1 (a state-based action). The inherent triggered ability of a player with speed (CR 702.179d)
      # has no source; the engine (Engine::Speed) puts it on the stack as this keyword's ability
      # "keyword:start_your_engines", which never triggers from the permanent itself (its zone is :rules).
      class StartYourEngines < Primitive
        primitive :keyword, :start_your_engines,
                  description: "If you control this permanent and have no speed, your speed becomes 1. Once you have " \
                               "speed, it increases by 1 (to at most 4) once on each of your turns when one or more " \
                               "opponents lose life. Pair with `max_speed` abilities and the `speed` amount.",
                  rules: %w[702.179a 702.179b 702.179c 702.179d 704.3],
                  example: { "keywords" => ["start_your_engines"] }

        # "Whenever one or more opponents lose life during your turn" (matched by Engine::Speed#watch_speed!).
        class OpponentsLoseLife
          def watches?(_event) = false
          def leaves_battlefield? = false
          def to_s = "Whenever one or more opponents lose life during your turn"
        end

        def self.intrinsic_abilities
          @intrinsic_abilities ||= [
            Abilities::TriggeredAbility.new(
              trigger: OpponentsLoseLife.new.freeze, targets: [].freeze, limit: "once_each_turn", zone: :rules,
              condition: Condition.build({ "amount" => { "speed" => "you" }, "at_most" => 3 }, [], "speed"),
              effects: [Effects::IncreaseSpeed.new(to: nil, params: {}, errors: [], path: "speed")].freeze
            )
          ].freeze
        end
      end
    end

    module Abilities
      # Max speed (CR 702.178a): "As long as your speed is 4, this object has [ability]." Like a station symbol,
      # its keywords and abilities are part of the object only while it applies; a card that isn't on the
      # battlefield uses its owner's speed (CR 702.178b, 113.6c: e.g. an ability activated from the graveyard).
      class MaxSpeed < Primitive
        primitive :ability, :max_speed,
                  description: "While your speed is 4 (max speed), this object has `keywords` and `abilities` (any " \
                               "kind: activated, triggered, static, mana; an ability with a graveyard cost works from " \
                               "your graveyard).",
                  rules: %w[702.178a 702.178b 702.179e 113.6c],
                  params: { "keywords" => "list of keywords", "abilities" => "list of abilities" },
                  example: { "max_speed" => { "abilities" => [{ "activated" => { "cost" => ["tap"],
                                                                                 "effects" => [{ "draw" => { "amount" => 1 } }] } }] } }

        attr_reader :keywords, :nested_abilities

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[keywords abilities], errors, path)
          keywords = StationSymbol.build_keywords(params, errors, path)
          abilities = StationSymbol.build_abilities(params, errors, path)
          abilities.each_with_index do |ability, i|
            errors << "#{path}.abilities[#{i}]: max speed abilities can't be nested" if ability.kind == :max_speed
          end
          errors << "#{path}: needs keywords or abilities" if keywords.empty? && abilities.empty?
          new(keywords, abilities)
        end

        def initialize(keywords, abilities)
          super()
          @keywords = keywords.freeze
          @nested_abilities = abilities.freeze
          freeze
        end

        def kind = :max_speed
        def power = nil
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "Max speed — #{(keywords.map(&:to_s) + nested_abilities.map(&:to_s)).join("; ")}"
      end
    end
  end
end
