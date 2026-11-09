# frozen_string_literal: true

module Enjine
  module Mechanics
    # A card filter for cards outside the battlefield: a CardSpec (`for`) plus card types the card must
    # not have (`not_types`, "a nonland card", "a noncreature spell").
    class CardFilter
      def self.build(params, errors, path)
        spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
        raw = Mechanics.fetch_param(params, :not_types) || []
        unless raw.is_a?(Array) && raw.all? { Enjine.registry.fetch(:type, it.to_s) }
          errors << "#{path}.not_types: must be a list of card types"
          raw = []
        end
        new(spec, raw.map(&:to_sym))
      end

      def initialize(spec, not_types)
        @spec = spec
        @not_types = not_types.freeze
        freeze
      end

      def match?(engine, obj) = @spec.match?(engine, obj) && !engine.chars(obj).types.intersect?(@not_types)

      def to_s
        words = @not_types.map { "non#{it}" }
        words.empty? ? @spec.to_s : "#{words.join(" ")} #{@spec}"
      end
    end

    module Abilities
      # A card's own permission to be cast from a zone other than the hand (CR 113.6e-f, 601.3), or a
      # permanent's static permission for its controller's cards in a zone, possibly limited to once per
      # turn (CR 604.1). Offered as cast / play_land options with a `via`.
      class PlayFrom < Primitive
        ZONES = %w[graveyard exile library_top].freeze
        PLAYS = %w[cast play].freeze

        primitive :ability, :play_from,
                  description: "With `cards: \"self\"` (default): its owner may cast this card from `zone` (the " \
                               "ability functions there). With a card spec: while this permanent is on the " \
                               "battlefield, its controller may play their own matching cards from `zone`. `play`: " \
                               "\"cast\" (spells only, default) or \"play\" (lands too). `once_each_turn`: once " \
                               "during each of your turns. `enters_with`: a permanent spell cast this way enters " \
                               "with these counters. Timing and costs are the usual ones.",
                  rules: %w[601.3 113.6e 113.6f 305.1 401.5 122.1 614.12],
                  params: { "zone" => ZONES.join(" | "), "cards" => "\"self\" or a card spec", "play" => PLAYS.join(" | "),
                            "once_each_turn" => "boolean", "enters_with" => "{counter name: n}" },
                  example: { "play_from" => { "zone" => "graveyard", "enters_with" => { "finality" => 1 } } }

        attr_reader :zone, :cards, :play, :once, :enters_with

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[zone cards play once_each_turn enters_with], errors, path)
          zone = Mechanics.fetch_param(params, :zone)
          errors << "#{path}.zone: must be one of #{ZONES.join(", ")}" unless ZONES.include?(zone)
          play = Mechanics.fetch_param(params, :play) || "cast"
          errors << "#{path}.play: must be one of #{PLAYS.join(", ")}" unless PLAYS.include?(play)
          raw = Mechanics.fetch_param(params, :cards) || "self"
          cards = raw == "self" ? :self : CardSpec.build(raw, errors, "#{path}.cards")
          once = Mechanics.fetch_param(params, :once_each_turn)
          errors << "#{path}.once_each_turn: must be true or false" unless [nil, true, false].include?(once)
          extra = Mechanics.fetch_param(params, :enters_with)
          extra &&= EntersWithCounters.read_counters(extra, errors, "#{path}.enters_with")
          new(zone, cards, play, once == true, extra)
        end

        def initialize(zone, cards, play, once, enters_with)
          super()
          @zone = zone
          @cards = cards
          @play = play
          @once = once
          @enters_with = enters_with&.freeze
          freeze
        end

        def self? = @cards == :self
        def kind = :play_from
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # Whether the card is in the zone this permission names.
        def holds?(engine, obj)
          return obj.zone == :library && engine.player(obj.owner).library.first == obj.id if zone == "library_top"

          obj.zone.to_s == zone
        end

        def to_s
          what = self? ? "this card" : "#{cards}s"
          where = zone == "library_top" ? "the top of your library" : "your #{zone}"
          text = "#{"Once during each of your turns, " if once}you may #{play} #{what} from #{where}"
          enters_with ? "#{text}; it enters with #{enters_with.map { |k, n| "#{n} #{k}" }.join(", ")} counter(s)" : text
        end
      end

      # Looking at the top card of your library at any time (CR 401.5).
      class LookAtTop < Primitive
        primitive :ability, :look_at_top,
                  description: "While this permanent is on the battlefield, its controller sees the top card of " \
                               "their library (the `library_top` of their view).",
                  rules: %w[401.5 604.1], example: "look_at_top"

        INSTANCE = new.freeze

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, [], errors, path)
          INSTANCE
        end

        def kind = :look_at_top
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []
        def to_s = "Its controller sees the top card of their library (CR 401.5)"
      end
    end

    module Effects
      # (exile_top, exiling the top N cards: see effects/library.rb.)

      # Exiling cards from the top of a library one at a time until a nonland card is exiled (CR 701.13).
      class ExileUntil < Effect
        UNTIL = %w[nonland].freeze

        primitive :effect, :exile_until,
                  description: "Each referenced player exiles cards from the top of their library until they exile a " \
                               "card matching `until` (or the library is empty). All exiled cards are the result.",
                  rules: %w[406.1 701.13a 400.7j], params: { "until" => UNTIL.join(" | "), "to" => "selector" },
                  example: { "exile_until" => { "until" => "nonland", "to" => { "target" => 0 } } }

        def self.keys = %w[until to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @until = Mechanics.fetch_param(params, :until)
          errors << "#{path}.until: must be one of #{UNTIL.join(", ")}" unless UNTIL.include?(@until)
        end

        def to_s = "exile from the top until a #{@until} card → #{to}"

        def apply(engine, ctx)
          players(engine, ctx).each do |index|
            library = engine.player(index).library
            until library.empty?
              exiled = engine.move!(library.first, :exile, reason: "exile")
              break if exiled.nil? || !engine.chars(exiled).land?
            end
          end
        end
      end

      # Permission to play exiled cards for a duration (CR 611.2, 601.3; see Engine::Permissions). With
      # `choose`, the controller first chooses one matching card per owner among them.
      class PlayPermission < ChoiceEffect
        DURATIONS = %w[end_of_turn end_of_your_next_turn while_exiled].freeze

        primitive :effect, :play_permission,
                  description: "The controller may play (`play: \"play\"`, default) or cast (`\"cast\"`) each referenced " \
                               "exiled card matching `for`/`not_types`, paying its costs and following timing rules, " \
                               "for `duration`: end_of_turn (default), end_of_your_next_turn or while_exiled. With " \
                               "`choose: \"one_per_owner\"` only one chosen card per owner. `player`: who gets the " \
                               "permission instead of the controller (a face-down card: only someone who may look at " \
                               "it). `any_mana_type: true`: mana of any type can be spent to cast those spells.",
                  rules: %w[611.2a 601.3 305.1 400.7 514.2 406.3b 609.4b],
                  params: { "to" => "selector (usually {\"result\": n})", "duration" => DURATIONS.join(" | "),
                            "play" => "play | cast", "for" => "card spec", "not_types" => "list of card types",
                            "choose" => "one_per_owner", "player" => "selector of players (default \"you\")",
                            "any_mana_type" => "boolean" },
                  example: { "play_permission" => { "to" => { "result" => 0 }, "duration" => "end_of_your_next_turn" } }

        def self.keys = %w[to duration play for not_types choose player any_mana_type if]

        def setup(params, errors, path)
          @duration = Mechanics.fetch_param(params, :duration) || "end_of_turn"
          durations = DURATIONS
          errors << "#{path}.duration: must be one of #{durations.join(", ")}" unless durations.include?(@duration)
          @play = Mechanics.fetch_param(params, :play) || "play"
          errors << "#{path}.play: must be play or cast" unless %w[play cast].include?(@play)
          @choose = Mechanics.fetch_param(params, :choose)
          errors << "#{path}.choose: must be one_per_owner" unless [nil, "one_per_owner"].include?(@choose)
          @filter = CardFilter.build(params, errors, path)
          @any_type = Mechanics.fetch_param(params, :any_mana_type)
          errors << "#{path}.any_mana_type: must be true or false" unless [nil, true, false].include?(@any_type)
          raw = Mechanics.fetch_param(params, :player)
          @player = raw && Selector.build(raw, errors, "#{path}.player", targets_count: @targets_count,
                                                                         results_count: @results_count)
        end

        def to_s
          who = @player ? "#{@player} may" : "you may"
          "#{who} #{@play} #{@filter} (#{@duration.tr("_", " ")})#{", mana of any type" if @any_type} → #{to}"
        end

        def run(engine, ctx, locals)
          return :done unless locals["cards"] || condition.nil? || condition.true?(engine, ctx)

          cards = (locals["cards"] ||= refs(engine, ctx).select { exiled_match?(engine, it) })
          picks = @choose ? choose(engine, ctx, locals, cards) : cards
          return :wait if picks == :wait

          grantees(engine, ctx).each do |index|
            engine.grant_play_permission!(index, picks, duration: @duration, play: @play, any_mana_type: @any_type == true)
          end
          :done
        end

        private

        def grantees(engine, ctx)
          return [ctx.controller] unless @player

          @player.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }.uniq
        end

        # A face-down card is judged face up (the permission is to play it face up, CR 406.3a).
        def exiled_match?(engine, id)
          obj = engine.state.objects[id]
          obj && obj.zone == :exile && engine.face_up(id) { @filter.match?(engine, obj) }
        end

        # One card per owner, in seat order; asked only when there's a choice.
        def choose(engine, ctx, locals, cards)
          asked = 0
          cards.group_by { engine.object(it).owner }.sort.map do |_owner, group|
            next group.first if group.size == 1

            answer = answers(locals)[asked]
            asked += 1
            next answer["object"] if answer

            return ask(engine, locals, ctx.controller, "Choose a card (#{@filter}) you may play",
                       group.map { { "type" => "choose", "object" => it } })
          end
        end
      end

      # Optional casting without paying mana costs during resolution (CR 608.2g, 118.9, 601.2a):
      # the controller picks a card, casts it right away (a cast frame on top of the resolving one; nobody
      # gets priority), then the resolution goes on. `count: "any"` repeats until they stop.
      class CastFree < ChoiceEffect
        primitive :effect, :cast_free,
                  description: "The controller may cast referenced cards without paying their mana costs while this " \
                               "resolves. `to` names the cards ({\"result\": n}), or a player for the cards in their " \
                               "hand (default: your hand). Only cards matching `for`/`not_types` with mana value up to " \
                               "`max_mana_value` (optional amount) that could be cast now (legal targets). `count`: 1 " \
                               "(default) or \"any\" (any number, one at a time). X is 0 (CR 107.3b).",
                  rules: %w[608.2g 118.9 601.2a 107.3b 118.6a],
                  params: { "to" => "selector", "for" => "card spec", "not_types" => "list of card types",
                            "max_mana_value" => "amount", "count" => "1 or \"any\"" },
                  example: { "cast_free" => { "to" => { "result" => 0 }, "max_mana_value" => 3, "count" => "any" } }

        def self.keys = %w[to for not_types max_mana_value count if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @filter = CardFilter.build(params, errors, path)
          raw = Mechanics.fetch_param(params, :max_mana_value)
          @max = raw.nil? ? nil : Amount.build(raw, errors, "#{path}.max_mana_value", targets_count: @targets_count)
          @count = Mechanics.fetch_param(params, :count) || 1
          errors << "#{path}.count: must be 1 or \"any\"" unless [1, "any"].include?(@count)
        end

        def to_s = "you may cast #{@count == "any" ? "any number of" : "a"} #{@filter} free → #{to}"

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          settle_cast!(engine, locals)
          answer = answers(locals)[locals.fetch("seen", 0)]
          if answer
            locals["seen"] = locals.fetch("seen", 0) + 1
            return :done if answer["type"] == "done"

            locals["casting"] = answer["object"]
            engine.begin_cast!(index, answer["object"], via: via)
            return :wait
          end
          return :done if @count == 1 && locals["cast"].to_i >= 1

          choices = candidates(engine, ctx, locals).map { { "type" => "cast", "object" => it } }
          return :done if choices.empty?

          ask(engine, locals, index, prompt, choices + [{ "type" => "done" }])
        end

        # How the cards are cast (Engine::Permissions#play_method); Effects::Cast pays the costs instead.
        def via = "free"
        def prompt = "You may cast a spell without paying its mana cost"
        def castable_now?(engine, index, id) = engine.free_castable?(index, id)

        private

        # After the cast frame: the card left its zone (it was cast), or it's back (cancelled: declined).
        def settle_cast!(engine, locals)
          id = locals.delete("casting") or return
          engine.state.objects.key?(id) ? (locals["declined"] ||= []) << id : locals["cast"] = locals["cast"].to_i + 1
        end

        def candidates(engine, ctx, locals)
          limit = @max&.value(engine, ctx)
          cards(engine, ctx).select do |id|
            obj = engine.object(id)
            !locals.fetch("declined", []).include?(id) && @filter.match?(engine, obj) &&
              (limit.nil? || engine.chars(obj).mana_cost&.mana_value.to_i <= limit) && castable_now?(engine, ctx.controller, id)
          end
        end

        # Referenced cards still in the zone they were put in; a player stands for their hand.
        def cards(engine, ctx)
          refs(engine, ctx).flat_map do |ref|
            index = Filters.player_index(engine, ref)
            next engine.player(index).hand if index
            next [] unless engine.state.objects.key?(ref)

            %i[stack battlefield].include?(engine.object(ref).zone) ? [] : [ref]
          end
        end
      end

      # Discover N (CR 701.57a): exile from the top until a nonland card with mana value N or less; cast it
      # without paying its mana cost or put it into your hand; the rest go on the bottom in a random order.
      class Discover < ChoiceEffect
        primitive :effect, :discover,
                  description: "Discover `amount`: exile cards from the top of your library until you exile a nonland " \
                               "card with mana value `amount` or less. You may cast it without paying its mana cost; " \
                               "if you don't, it goes into your hand. The other exiled cards go on the bottom of " \
                               "your library in a random order.",
                  rules: %w[701.57a 701.57b 701.57c 608.2g 118.9],
                  params: { "amount" => "amount" },
                  example: { "discover" => { "amount" => 5 } }

        def self.keys = %w[amount if]
        def self.default_to = "you"

        def run(engine, ctx, locals)
          return :done unless locals["exiled"] || condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          exile_until_hit!(engine, ctx, locals) unless locals["exiled"]
          hit = locals["hit"]
          return :wait if hit && decide(engine, index, locals, hit) == :wait

          rest = (locals["exiled"] - [hit]).select { engine.state.exile.include?(it) }
          engine.state.rng.shuffle!(rest)
          rest.each { engine.move!(it, :library, position: :bottom, reason: "discover") }
          :done
        end

        private

        def exile_until_hit!(engine, ctx, locals)
          n = amount_for(engine, ctx)
          library = engine.player(ctx.controller).library
          locals["exiled"] = []
          until library.empty?
            card = engine.move!(library.first, :exile, reason: "discover") or break
            locals["exiled"] << card.id
            c = engine.chars(card)
            next if c.land? || c.mana_cost&.mana_value.to_i > n

            locals["hit"] = card.id
            break
          end
        end

        # Cast it (a frame), or into the hand; a cancelled cast puts it into the hand too.
        def decide(engine, index, locals, hit)
          return if locals["decided"]

          if locals.key?("casting")
            locals.delete("casting")
          else
            answer = answers(locals).first
            unless answer
              choices = [{ "type" => "hand", "object" => hit }]
              choices.unshift({ "type" => "cast", "object" => hit }) if engine.free_castable?(index, hit)
              return ask(engine, locals, index, "Discover: cast it without paying its mana cost, or put it into your hand",
                         choices)
            end
            if answer["type"] == "cast"
              locals["casting"] = hit
              engine.begin_cast!(index, hit, via: "free")
              return :wait
            end
          end
          locals["decided"] = true
          engine.move!(hit, :hand, reason: "discover") if engine.state.objects.key?(hit)
          nil
        end
      end
    end
  end
end
