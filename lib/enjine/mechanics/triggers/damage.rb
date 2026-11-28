# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # Which damage a damage trigger counts: `combat: true` only combat damage, `noncombat: true` only
      # noncombat damage (CR 120.2a-b).
      module DamageKind
        def setup_kind(params, errors, path)
          @combat = params.fetch("combat", false)
          @noncombat = params.fetch("noncombat", false)
          %w[combat noncombat].each do |key|
            errors << "#{path}.#{key}: must be true or false" unless [true, false].include?(params.fetch(key, false))
          end
          errors << "#{path}: combat and noncombat can't both be true" if @combat == true && @noncombat == true
        end

        def kind_ok?(event) = !(@combat && !event.combat) && !(@noncombat && event.combat)
        def kind_words = ("combat " if @combat) || ("noncombat " if @noncombat)
      end

      # "Whenever ~ deals combat damage to a player" / "Whenever a source you control deals noncombat damage
      # to an opponent" / "Whenever one or more creatures you control deal combat damage to a player" (`batched`).
      class DealsDamage < Trigger
        include DamageKind
        include Batched

        RECIPIENTS = %w[player opponent you creature planeswalker battle permanent any].freeze
        PERMANENT_TYPES = %w[creature planeswalker battle].freeze

        primitive :trigger, :deals_damage,
                  description: "The subject deals damage. `combat: true` only counts combat damage, `noncombat: true` " \
                               "only noncombat damage; `to`: player | opponent | you (players, relative to the " \
                               "source's controller) | creature | planeswalker | battle | permanent | any (default), " \
                               "or a list of them (\"a player or planeswalker\"). Triggers once per damage event " \
                               "(each combat damage step is one, so double strike can trigger twice). `batched: true`: " \
                               "\"one or more ... deal damage\", once per event batch (a combat damage step); then " \
                               "{\"triggering\": \"objects\"} are the sources that dealt it and {\"triggering\": " \
                               "\"amount\"} the number of damage events.",
                  rules: %w[510.2 603.2 603.2c 120.2a 120.2b 120.3],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}", "combat" => "true | false",
                            "noncombat" => "true | false", "to" => "#{RECIPIENTS.join(" | ")}, or a list of them",
                            "batched" => "true | false" },
                  example: { "deals_damage" => { "combat" => true, "to" => "player" } }

        def self.keys = %w[subject combat noncombat to batched]
        def event_class = Events::DamageDealt

        def setup(params, errors, path)
          setup_kind(params, errors, path)
          setup_batched(params, errors, path)
          @to = Array(params.fetch("to", "any"))
          return if !@to.empty? && (@to - RECIPIENTS).empty?

          errors << "#{path}.to: must be one of #{RECIPIENTS.join(", ")}, or a list of them"
        end

        def match?(engine, event, source)
          return false unless kind_ok?(event) && @to.any? { recipient_ok?(engine, event.target, source, it) }

          obj = engine.state.objects[event.source] or return false
          @subject.match?(engine, event.source, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        # The recipient as it is dealt damage (CR 120.3): a player relative to the source's controller, or a
        # permanent by its card types.
        def recipient_ok?(engine, ref, source, to)
          return true if to == "any"

          index = Filters.player_index(engine, ref)
          return %w[player opponent you].include?(to) && (to == "player" || (to == "you") == (index == source["controller"])) if index
          return false unless engine.state.objects.key?(ref)

          to == "permanent" || (PERMANENT_TYPES.include?(to) && engine.chars(ref).type?(to.to_sym))
        end

        def to_s
          to = @to == ["any"] ? "" : " to a#{"n" if @to.first == "opponent"} #{@to.join(" or ")}"
          "Whenever #{"one or more of " if @batched}#{@subject} deal#{"s" unless @batched} #{kind_words}damage#{to}"
        end
      end

      # "Whenever this creature is dealt damage", "Whenever enchanted creature is dealt damage", "Whenever an
      # opponent is dealt noncombat damage" (CR 120.3, 603.2). "That creature" is the one dealt damage and
      # "that much" the damage dealt.
      class DealtDamage < Trigger
        include DamageKind
        include Batched

        primitive :trigger, :dealt_damage,
                  description: "Damage is dealt to the `subject` (a permanent: \"self\" by default, \"attached\" or " \
                               "{\"each\": filter, ...}) or, with `player` (you | opponent | any), to a player. " \
                               "`combat` / `noncombat`: only that damage. {\"triggering\": \"object\"} is the permanent " \
                               "dealt damage, {\"triggering\": \"player\"} the player, {\"triggering\": \"amount\"} how " \
                               "much. `batched: true`: \"one or more ...\" (once per damage event, CR 603.2c).",
                  rules: %w[120.3 603.2 603.2c 120.2a 120.2b],
                  params: { "subject" => "\"self\" (default), \"attached\" or {\"each\": filter, ...}",
                            "player" => PLAYERS.join(" | "), "combat" => "true | false", "noncombat" => "true | false",
                            "batched" => "true | false" },
                  example: { "dealt_damage" => { "subject" => "self" } }

        def self.keys = %w[subject player combat noncombat batched]
        def event_class = Events::DamageDealt

        def setup(params, errors, path)
          setup_kind(params, errors, path)
          setup_batched(params, errors, path)
          @player = params["player"]
          errors << "#{path}.player: must be one of #{PLAYERS.join(", ")}" unless @player.nil? || PLAYERS.include?(@player)
          errors << "#{path}: use subject or player, not both" if @player && params.key?("subject")
        end

        def match?(engine, event, source)
          return false unless kind_ok?(event)

          index = Filters.player_index(engine, event.target)
          return player_ok?(index, source) if index
          return false if @player

          obj = engine.state.objects[event.target] or return false
          @subject.match?(engine, event.target, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def player_ok?(index, source)
          return false unless @player

          @player == "any" || (@player == "you") == (index == source["controller"])
        end

        def occurrences(engine, event, source)
          return [] unless match?(engine, event, source)

          facts = { "amount" => event.amount }
          index = Filters.player_index(engine, event.target)
          [index ? facts.merge("player" => index) : facts.merge("object" => event.target, "card" => engine.object(event.target).card)]
        end

        def to_s
          who = @player ? { "you" => "you are", "opponent" => "an opponent is", "any" => "a player is" }[@player] : "#{@subject} is"
          "Whenever #{who} dealt #{kind_words}damage"
        end
      end
    end
  end
end
