# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
      # Cards an effect puts onto the battlefield under one player's control: each one's "as this enters"
      # choice is made first, one card at a time, then they all enter at once (CR 614.12, 614.12a). The
      # including effect has a `put` zone; other zones move one card at a time as before.
      module EntersBattlefield
        # Whether a choice is now pending (the effect returns :wait and asks again on resume).
        def entering_choices?(engine, controller, locals, ids)
          @put.to_s == "battlefield" && engine.ask_entering_choices!(locals, ids.map { [it, controller] }) == :wait
        end

        # Moves the cards to `@put`; onto the battlefield, under `controller`'s control and all at once.
        def put_cards!(engine, locals, ids, controller, reason:, enters: nil)
          return engine.enter_battlefield!(locals, ids.map { [it, controller, enters] }, reason: reason) if @put.to_s == "battlefield"

          ids.each { engine.move!(it, @put.to_sym, reason: reason, enters: enters) }
        end
      end

      # Where the cards a library effect didn't take go: the bottom of the library in a random order or in
      # an order the player chooses (CR 401.4), or the graveyard.
      module RestOfCards
        REST = %w[bottom_random bottom_any graveyard].freeze

        def parse_rest(params, errors, path)
          rest = (Mechanics.fetch_param(params, :rest) || "bottom_random").to_s
          errors << "#{path}.rest: must be one of #{REST.join(", ")}" unless REST.include?(rest)
          rest
        end

        # Asks for the bottom order one card at a time ("the first chosen goes on the bottom first").
        # Returns :wait while asking, else places the cards.
        def place_rest(engine, locals, index, rest_ids)
          if @rest == "graveyard"
            engine.unrecorded { rest_ids.each { engine.move!(it, :graveyard, reason: "put") } }
            return :done
          end
          if @rest == "bottom_any"
            order = answers(locals).select { it["type"] == "bottom" }.map { it["object"] }
            left = rest_ids - order
            if left.size > 1
              return ask(engine, locals, index, "Choose the next card to put on the bottom of your library",
                         left.map { { "type" => "bottom", "object" => it } })
            end
            rest_ids = order + left
          end
          engine.put_on_bottom!(index, rest_ids, random: @rest == "bottom_random")
          :done
        end
      end

      # Look at (or reveal) the top N cards of your library, take the ones matching a card spec (all, a
      # number, or up to a number), then put the rest away (CR 701.20a, 701.20e, 401.4).
      class Dig < ChoiceEffect
        include RestOfCards
        include EntersBattlefield

        PUT = %w[hand battlefield graveyard].freeze
        REVEAL = %w[none chosen all].freeze

        primitive :effect, :dig,
                  description: "Look at the top `amount` cards of your library (`reveal: \"all\"`: reveal them). Take " \
                               "`count` (default 1; \"all\": every matching card, no choice) cards matching `for` and put " \
                               "them into `put` (`tapped` onto the battlefield); `optional`: you may take fewer. " \
                               "`reveal: \"chosen\"` reveals the cards taken. The rest go to `rest`: \"bottom_random\" " \
                               "(default), \"bottom_any\" (in an order you choose) or \"graveyard\".",
                  rules: %w[701.20a 701.20e 401.4 400.7j],
                  params: { "amount" => "amount (how many cards)", "for" => "card spec (default any card)",
                            "count" => "integer or \"all\"", "optional" => "boolean", "put" => PUT.join(" | "),
                            "tapped" => "boolean", "reveal" => REVEAL.join(" | "), "rest" => RestOfCards::REST.join(" | ") },
                  example: { "dig" => { "amount" => 6, "for" => { "types" => ["artifact"] }, "optional" => true,
                                        "reveal" => "chosen", "put" => "hand" } }

        attr_reader :spec, :count, :put

        def self.keys = %w[amount for count optional put tapped reveal rest if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          @count = Mechanics.fetch_param(params, :count) || 1
          unless @count == "all" || (@count.is_a?(Integer) && @count.positive?)
            errors << "#{path}.count: must be a positive integer or \"all\""
          end
          @optional = Mechanics.flag_param(params, "optional", errors, path)
          @put = (Mechanics.fetch_param(params, :put) || "hand").to_s
          errors << "#{path}.put: must be one of #{PUT.join(", ")}" unless PUT.include?(@put)
          @tapped = Mechanics.flag_param(params, "tapped", errors, path)
          @reveal = (Mechanics.fetch_param(params, :reveal) || "none").to_s
          errors << "#{path}.reveal: must be one of #{REVEAL.join(", ")}" unless REVEAL.include?(@reveal)
          @rest = parse_rest(params, errors, path)
        end

        def to_s
          many = count == "all" ? "all" : "#{"up to " if @optional}#{count}"
          "#{@reveal == "all" ? "reveal" : "look at"} the top #{amount} cards, #{many} #{spec} → #{put}, rest → " \
            "#{@rest.tr("_", " ")}"
        end

        def run(engine, ctx, locals)
          return :done unless locals.key?("seen") || condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          seen = (locals["seen"] ||= first_look(engine, ctx, index))
          unless locals["taken"]
            taken = answers(locals).select { it["type"] == "take" }.map { it["object"] }
            choices = count == "all" ? [] : choices(engine, ctx, seen, taken, locals)
            return ask(engine, locals, index, "Choose #{spec} to take", choices) unless choices.empty?

            taken = seen.select { spec.match?(engine, engine.object(it), ctx) } if count == "all"
            return :wait if entering_choices?(engine, ctx.controller, locals, taken)

            take!(engine, ctx, index, taken, locals)
            locals["taken"] = taken
          end
          place_rest(engine, locals, index, seen - locals["taken"])
        end

        private

        def first_look(engine, ctx, index)
          seen = engine.player(index).library.first(amount_for(engine, ctx))
          @reveal == "all" ? engine.reveal!(index, seen) : engine.look_at!(index, index, seen)
          seen
        end

        def choices(engine, ctx, seen, taken, locals)
          return [] if answers(locals).any? { it["type"] == "done" } || taken.size >= count

          ids = (seen - taken).select { spec.match?(engine, engine.object(it), ctx) }
          options = ids.uniq { engine.object(it).card }.map { { "type" => "take", "object" => it } }
          options << { "type" => "done" } if @optional && !options.empty?
          options
        end

        def take!(engine, ctx, index, taken, locals)
          engine.reveal!(index, taken) if @reveal == "chosen"
          put_cards!(engine, locals, taken, ctx.controller, reason: "put", enters: @tapped ? { "tapped" => true } : nil)
        end
      end

      # Reveal cards from the top of your library one at a time until N cards matching a spec are revealed;
      # those go to a zone, the other revealed cards are put away (CR 701.20a, 401.4).
      class RevealUntil < ChoiceEffect
        include RestOfCards
        include EntersBattlefield

        PUT = %w[hand battlefield].freeze

        primitive :effect, :reveal_until,
                  description: "Reveal cards from the top of your library until `count` (an amount, default 1) cards " \
                               "matching `for` are revealed (or the library runs out). Put those into `put` " \
                               "(`tapped` onto the battlefield, under your control) and the rest to `rest` (default " \
                               "the bottom in a random order).",
                  rules: %w[701.20a 401.4 400.7j],
                  params: { "for" => "card spec", "count" => "amount", "put" => PUT.join(" | "), "tapped" => "boolean",
                            "rest" => RestOfCards::REST.join(" | ") },
                  example: { "reveal_until" => { "for" => { "types" => ["land"] }, "count" => 2, "put" => "battlefield",
                                                 "tapped" => true } }

        def self.keys = %w[for count put tapped rest if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          @count = Amount.build(Mechanics.fetch_param(params, :count) || 1, errors, "#{path}.count", targets_count: @targets_count)
          @put = (Mechanics.fetch_param(params, :put) || "hand").to_s
          errors << "#{path}.put: must be one of #{PUT.join(", ")}" unless PUT.include?(@put)
          @tapped = Mechanics.flag_param(params, "tapped", errors, path)
          @rest = parse_rest(params, errors, path)
        end

        def to_s = "reveal until #{@count} #{@spec} → #{@put}#{" tapped" if @tapped}, rest → #{@rest.tr("_", " ")}"

        def run(engine, ctx, locals)
          return :done unless locals.key?("found") || condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          unless locals.key?("found")
            revealed, found = reveal(engine, ctx, index)
            locals["found"] = found
            locals["rest"] = revealed - found
          end
          unless locals["moved"]
            return :wait if entering_choices?(engine, index, locals, locals["found"])

            put_cards!(engine, locals, locals["found"], index, reason: "put", enters: @tapped ? { "tapped" => true } : nil)
            locals["moved"] = true
          end
          place_rest(engine, locals, index, locals["rest"])
        end

        private

        def reveal(engine, ctx, index)
          wanted = @count.value(engine, ctx)
          revealed = []
          found = []
          engine.player(index).library.each do |id|
            break if found.size >= wanted

            revealed << id
            found << id if @spec.match?(engine, engine.object(id), ctx)
          end
          engine.reveal!(index, revealed)
          [revealed, found]
        end
      end

      # Exile the top N cards of a library (CR 406.1). What was exiled is the effect's result ({"result": n}),
      # for later effects of the list (returning the permanent cards among them, permissions to play them);
      # `link: true` exiles them with the source (CR 607.2a).
      class ExileTop < Effect
        primitive :effect, :exile_top,
                  description: "Each referenced player (default: you) exiles the top `amount` cards of their library " \
                               "(face up). Later effects name them with {\"result\": n}; `link: true` exiles them with " \
                               "the source. `face_down: true` exiles them face down: only the `looker` players " \
                               "(default: you) may look at them.",
                  rules: %w[406.1 400.7j 607.2a 406.3 406.3a],
                  params: { "amount" => "amount", "to" => "selector of players", "link" => "boolean",
                            "face_down" => "boolean", "looker" => "selector of players who may look (default \"you\")" },
                  example: { "exile_top" => { "amount" => 4 } }

        def self.keys = %w[amount to link face_down looker if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @link = Mechanics.flag_param(params, "link", errors, path)
          @face_down = Mechanics.flag_param(params, :face_down, errors, path)
          raw = Mechanics.fetch_param(params, :looker)
          errors << "#{path}.looker: needs face_down: true" if raw && !@face_down
          @looker = Selector.build(raw || "you", errors, "#{path}.looker", targets_count: @targets_count,
                                                                           results_count: @results_count)
        end

        def to_s = @face_down ? super.sub(" → ", " face down → ") : super

        def apply(engine, ctx)
          n = amount_for(engine, ctx)
          lookers = @face_down ? @looker.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) } : nil
          players(engine, ctx).each do |index|
            engine.player(index).library.first(n).each do |id|
              fresh = engine.move!(id, :exile, reason: "exile", face_down: lookers)
              engine.link_exiled!(ctx.source, fresh.id) if fresh && @link
            end
          end
        end
      end

      # Explore (CR 701.44a): reveal the top card of your library; a land card goes to your hand,
      # otherwise the exploring permanent gets a +1/+1 counter and you may put the card into your graveyard.
      class Explore < ChoiceEffect
        primitive :effect, :explore,
                  description: "Each referenced permanent explores: its controller reveals the top card of their " \
                               "library. A land card goes to their hand; otherwise the permanent gets a +1/+1 counter " \
                               "(if it's still on the battlefield) and they may put the card into their graveyard.",
                  rules: %w[701.44a 701.44b 701.44c],
                  params: { "to" => "selector of permanents" },
                  example: { "explore" => { "to" => "self" } }

        def self.keys = %w[to if]

        def run(engine, ctx, locals)
          return :done unless locals.key?("queue") || condition.nil? || condition.true?(engine, ctx)

          queue = (locals["queue"] ||= refs(engine, ctx).select { engine.state.objects.key?(it) })
          while (id = queue.first)
            return :wait if explore(engine, ctx, locals, id) == :wait

            queue.shift
            locals.delete("card")
            locals.delete("answers")
          end
          :done
        end

        private

        # CR 701.44c: a permanent that has left uses its last known controller (here: the effect's controller).
        def explore(engine, ctx, locals, id)
          obj = engine.object(id)
          index = obj.zone == :battlefield ? obj.controller : ctx.controller
          unless locals.key?("card")
            locals["card"] = engine.player(index).library.first
            return land_or_counter(engine, locals, id, index)
          end
          answer = answers(locals).first
          card = locals["card"]
          engine.move!(card, :graveyard, reason: "explore") if answer["type"] == "graveyard"
          :done
        end

        def land_or_counter(engine, locals, id, index)
          card = locals["card"]
          engine.reveal!(index, [card]) if card
          if card && engine.chars(card).land?
            engine.move!(card, :hand, reason: "explore")
            return :done
          end
          engine.add_counters!(engine.object(id), "+1/+1", 1, by_player: index) if engine.state.battlefield.include?(id)
          return :done unless card

          ask(engine, locals, index, "Explore: keep the revealed card on top or put it into your graveyard?",
              [{ "type" => "top", "object" => card }, { "type" => "graveyard", "object" => card }])
        end
      end
    end
  end
end
