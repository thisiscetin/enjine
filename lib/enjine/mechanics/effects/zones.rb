# frozen_string_literal: true

module Enjine
  module Mechanics
    # Linked abilities (CR 607.2a, 406.6): cards an ability of a source exiled are kept in the source's
    # memory, so another ability of the same object can name "the cards exiled with it". A source that
    # changes zones is a new object (CR 400.7) with no memory, so the link ends with it. Also the last
    # known controller of objects a resolving effect moved (CR 608.2h), for {"controller_of": selector}.
    module Linked
      EXILED = "exiled_with"
      UNTIL_LEAVES = "until_leaves"
      LKI = "lki"

      def self.flag(params, key, errors, path)
        value = Mechanics.fetch_param(params, key)
        errors << "#{path}.#{key}: must be true or false" unless [nil, true, false].include?(value)
        value == true
      end

      # Cards still in exile that an ability of `source` exiled (CR 607.2a).
      def self.exiled_with(engine, source)
        obj = engine.state.objects[source] or return []
        obj.memory.fetch(EXILED, []).select { engine.state.exile.include?(it) }
      end

      # Called by a resolving effect before it moves an object: who controlled it (CR 608.2h), kept on the
      # resolving spell or ability. Only a permanent has a controller other than its owner.
      def self.remember!(engine, ctx, id)
        obj = engine.object(id)
        (engine.object(ctx.object).memory[LKI] ||= {})[id] = obj.controller if obj.zone == :battlefield
      end

      # An amount whose {"count": selector} may name earlier effects' results ("up to that many").
      def self.amount(raw, errors, path, targets_count, results_count)
        return Amount.build(raw, errors, path, targets_count: targets_count) unless raw.is_a?(Hash) && raw.keys.map(&:to_s) == ["count"]

        Amount.new("count", Selector.build(raw.values.first, errors, "#{path}.count", targets_count: targets_count,
                                                                                      results_count: results_count))
      end
    end

    class Condition
      # Whether the referenced objects (e.g. the cards exiled with a source, CR 607.2a) have at least one
      # card type in common. No objects share nothing.
      class ShareCardType
        def self.build(data, errors, path, targets_count)
          Mechanics.check_keys(data, %w[share_card_type], errors, path)
          new(Selector.build(data["share_card_type"], errors, "#{path}.share_card_type", targets_count: targets_count))
        end

        def initialize(selector)
          @selector = selector
          freeze
        end

        def true?(engine, ctx)
          objects = @selector.resolve(engine, ctx).filter_map { engine.state.objects[it] }
          !objects.empty? && !objects.map { engine.chars(it).types }.reduce(:&).empty?
        end

        def to_s = "#{@selector} share a card type"
      end
    end

    module Effects
      # Runs a nested effect list one effect at a time (as `may` does); a waiting effect keeps its locals
      # under "child", where Engine#effect_answer! delivers answers.
      module NestedList
        def run_list(engine, ctx, locals, list)
          while locals["next"] < list.size
            return :wait if list[locals["next"]].run(engine, ctx, locals["child"] ||= {}) == :wait

            locals.delete("child")
            locals["next"] += 1
          end
          :done
        end

        def parse_lists(params, errors, path, keys)
          keys.to_h do |key|
            [key, Abilities::StackAbility.parse_effects(params, errors, path, @targets_count, key: key.to_sym,
                                                                                              results_count: @results_count)]
          end.freeze
        end
      end

      # Choose cards from among a set (CR 700.2-style choices made on resolution): from what an earlier
      # effect moved ({"result": n}), from a player's hand or graveyard, or from permanents. The chosen
      # cards go to `put`; `then` follows if a card was chosen ("if you do"), `otherwise` if none was
      # ("if you can't" / "if you don't").
      class ChooseCards < ChoiceEffect
        include NestedList

        PUT = %w[hand graveyard exile battlefield library_top library_bottom].freeze
        ZONES = %w[hand graveyard].freeze
        REVEAL = %w[chosen all].freeze
        LISTS = %w[then otherwise].freeze

        primitive :effect, :choose_cards,
                  description: "You choose `count` (default 1; \"any\": any number) cards matching `for` from `from`: a " \
                               "selector (e.g. {\"result\": 0}, the cards an earlier effect milled) or a player's zone, " \
                               "{\"hand\": selector} / {\"graveyard\": selector}. `optional`: you may choose fewer. Then " \
                               "they are put into `put` (`tapped` onto the battlefield, under your control; exiled cards " \
                               "`link`ed to the source). `look`: you look at the whole zone first; `reveal`: \"chosen\" " \
                               "reveals what you chose, \"all\" the whole set. `then` runs if a card was chosen, " \
                               "`otherwise` if none was (\"if you can't\").",
                  rules: %w[701.20a 701.20e 400.7j 608.2c 607.2a 118.12],
                  params: { "from" => "selector or {\"hand\"|\"graveyard\": player selector}", "for" => "card spec",
                            "count" => "integer or \"any\"", "optional" => "boolean", "put" => PUT.join(" | "),
                            "tapped" => "boolean", "link" => "boolean", "look" => "boolean",
                            "reveal" => REVEAL.join(" | "), "then" => "list of effects", "otherwise" => "list of effects" },
                  example: { "choose_cards" => { "from" => { "result" => 0 }, "for" => { "permanent" => true },
                                                 "optional" => true, "put" => "hand" } }

        attr_reader :spec, :count, :put

        def self.keys = %w[from for count optional put tapped link look reveal then otherwise if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @from_zone, @from = parse_from(Mechanics.fetch_param(params, :from), errors, path)
          @spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          @count = Mechanics.fetch_param(params, :count) || 1
          unless @count == "any" || (@count.is_a?(Integer) && @count.positive?)
            errors << "#{path}.count: must be a positive integer or \"any\""
          end
          @optional = Linked.flag(params, "optional", errors, path)
          @put = Mechanics.fetch_param(params, :put).to_s
          errors << "#{path}.put: must be one of #{PUT.join(", ")}" unless PUT.include?(@put)
          @flags = %w[tapped link look].to_h { [it, Linked.flag(params, it, errors, path)] }
          @reveal = Mechanics.fetch_param(params, :reveal)
          errors << "#{path}.reveal: must be one of #{REVEAL.join(", ")}" unless @reveal.nil? || REVEAL.include?(@reveal)
          @lists = parse_lists(params, errors, path, LISTS)
        end

        def parse_from(raw, errors, path)
          zone = raw.is_a?(Hash) && raw.size == 1 && ZONES.include?(raw.keys.first.to_s) ? raw.keys.first.to_s : nil
          inner = zone ? raw.values.first : raw
          return [zone, nil] if inner.nil? && (errors << "#{path}.from: required")

          [zone, Selector.build(inner, errors, "#{path}.from#{".#{zone}" if zone}", targets_count: @targets_count,
                                                                                    results_count: @results_count)]
        end

        def nested_effects = @lists.values.flatten

        def to_s
          many = count == "any" ? "any number of" : "#{"up to " if @optional}#{count}"
          "choose #{many} #{spec} from #{"the #{@from_zone} of " if @from_zone}#{@from} → #{put.tr("_", " ")}"
        end

        # CR 118.3: as the optional part of a "may", the full number of cards must be available.
        def possible?(engine, ctx) = pool(engine, ctx).size >= (count == "any" ? 1 : count)

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || locals.key?("chose") || condition.nil? || condition.true?(engine, ctx)

          unless locals.key?("chose")
            show!(engine, ctx, locals)
            chosen = answers(locals).select { it["type"] == "choose" }.map { it["object"] }
            choices = stop?(locals, chosen) ? [] : choices(engine, ctx, chosen)
            return ask(engine, locals, ctx.controller, "Choose #{spec}", choices) unless choices.empty?

            return :wait if put == "battlefield" && engine.ask_entering_choices!(locals, chosen.map { [it, ctx.controller] }) == :wait

            locals["chose"] = !perform!(engine, ctx, chosen, locals).empty?
            locals["next"] = 0
          end
          run_list(engine, ctx, locals, @lists[locals["chose"] ? "then" : "otherwise"])
        end

        private

        # The cards to choose from, in a stable order.
        def pool(engine, ctx)
          refs = set(engine, ctx)
          refs.select { (obj = engine.state.objects[it]) && spec.match?(engine, obj, ctx) }
        end

        def set(engine, ctx)
          refs = @from.resolve(engine, ctx)
          return refs.select { engine.state.objects.key?(it) } unless @from_zone

          refs.filter_map { Filters.player_index(engine, it) }.flat_map { engine.player(it).public_send(@from_zone) }
        end

        # Looking at or revealing the whole set happens once, before the choice (CR 701.20a, 701.20e).
        def show!(engine, ctx, locals)
          return if locals["shown"]

          locals["shown"] = true
          ids = set(engine, ctx)
          if @reveal == "all"
            ids.group_by { engine.object(it).owner }.each_value { engine.reveal!(engine.object(it.first).owner, it) }
          elsif @flags["look"]
            ids.group_by { engine.object(it).owner }.each { |owner, list| engine.look_at!(ctx.controller, owner, list) }
          end
        end

        def stop?(locals, chosen)
          answers(locals).any? { it["type"] == "done" } || (count != "any" && chosen.size >= count)
        end

        def choices(engine, ctx, chosen)
          ids = pool(engine, ctx) - chosen
          options = ids.map { { "type" => "choose", "object" => it } }
          return options if options.empty?

          options << { "type" => "done" } if @optional || count == "any"
          options
        end

        def perform!(engine, ctx, chosen, locals)
          engine.reveal!(ctx.controller, chosen) if @reveal == "chosen"
          return enter!(engine, ctx, chosen, locals) if put == "battlefield"

          chosen.filter_map { move(engine, ctx, it) }
        end

        # CR 614.12a: their "as this enters" choices were made first; they enter at the same time.
        def enter!(engine, ctx, chosen, locals)
          enters = @flags["tapped"] ? { "tapped" => true } : nil
          engine.enter_battlefield!(locals, chosen.map { [it, ctx.controller, enters] }, reason: "put")
        end

        def move(engine, ctx, id)
          case put
          when "library_top", "library_bottom"
            engine.move!(id, :library, reason: "put", position: put == "library_top" ? :top : :bottom)
          else
            fresh = engine.move!(id, put.to_sym, reason: put == "graveyard" ? "put" : put)
            engine.link_exiled!(ctx.source, fresh.id) if fresh && @flags["link"]
            fresh
          end
        end
      end

      # Edicts and sacrifices of the player's choice: each referenced player chooses a number of permanents
      # they control matching `filter`, in APNAP order (CR 101.4); then all of them are sacrificed at the
      # same time (CR 701.21a).
      class SacrificeChoice < ChoiceEffect
        primitive :effect, :sacrifice_choice,
                  description: "Each referenced player (default: you) sacrifices `count` (default 1; \"any\": any number) " \
                               "permanents they control matching `filter`, chosen by them in turn order starting with " \
                               "the active player; all are sacrificed at once. The `filter`'s `controller` and `other` " \
                               "restrictions are relative to the effect's controller and source.",
                  rules: %w[701.21a 101.4 118.3],
                  params: { "filter" => "a filter, e.g. {\"creature\": {\"token\": false}}", "count" => "integer or \"any\"",
                            "to" => "selector of players" },
                  example: { "sacrifice_choice" => { "filter" => "creature", "to" => "each_opponent" } }

        attr_reader :filter, :count

        def self.keys = %w[filter count to if]
        def self.default_to = "you"

        def setup(params, errors, path)
          raw = Mechanics.fetch_param(params, :filter)
          errors << "#{path}.filter: required" if raw.nil?
          @filter = raw && Mechanics.build_entry(:filter, raw, errors, "#{path}.filter")
          @count = Mechanics.fetch_param(params, :count) || 1
          return if @count == "any" || (@count.is_a?(Integer) && @count.positive?)

          errors << "#{path}.count: must be a positive integer or \"any\""
        end

        def to_s = "#{to} sacrifices #{count == "any" ? "any number of" : count} #{words} of their choice"
        def words = filter.is_a?(Class) ? filter.primitive_name.tr("_", " ") : filter.to_s

        # CR 118.3: as the optional part of a "may", there must be enough permanents to sacrifice.
        def possible?(engine, ctx)
          players(engine, ctx).all? { candidates(engine, ctx, it, []).size >= (count == "any" ? 0 : count) }
        end

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || locals.key?("queue") || condition.nil? || condition.true?(engine, ctx)

          queue = (locals["queue"] ||= apnap(engine, players(engine, ctx)))
          picks = (locals["picks"] ||= [])
          take_answers(locals, picks)
          while (index = queue.first)
            mine = picks.select { it[0] == index }.map { it[1] }
            ask_for = remaining(engine, ctx, locals, index, mine)
            return ask_for if ask_for == :wait

            queue.shift
          end
          picks.each { finish!(engine, it[1]) }
          :done
        end

        # Hooks for Effects::ReturnChoice: what happens to the chosen permanents, who may choose one.
        def finish!(engine, id) = engine.move!(id, :graveyard, reason: "sacrifice")
        def choosable?(engine, obj, index) = engine.can_sacrifice?(obj, index)
        def verb = "sacrifice"

        private

        def apnap(engine, indexes) = engine.turn_order_from_active.select { indexes.include?(it) }

        # Permanents `index` controls that match the filter, not yet chosen.
        def candidates(engine, ctx, index, chosen)
          filter.candidates_for(engine, ctx.controller, ctx.source)
                .select { engine.state.objects.key?(it) && choosable?(engine, engine.object(it), index) } - chosen
        end

        # Asks `index` for their next permanent, or picks automatically when there is no real choice.
        def remaining(engine, ctx, locals, index, mine)
          left = candidates(engine, ctx, index, mine)
          return :next if left.empty? || locals["stopped"] == index || (count != "any" && mine.size >= count)

          if count != "any" && left.size <= count - mine.size
            left.each { locals["picks"] << [index, it] }
            return :next
          end
          choices = left.map { { "type" => verb, "object" => it } }
          choices << { "type" => "done" } if count == "any"
          locals["chooser"] = index
          ask(engine, locals, index, "#{verb.capitalize} #{words}", choices)
        end

        def take_answers(locals, picks)
          (locals["taken"] ||= 0).upto(answers(locals).size - 1) do |i|
            answer = answers(locals)[i]
            answer["type"] == "done" ? locals["stopped"] = locals["chooser"] : picks << [locals["chooser"], answer["object"]]
          end
          locals["taken"] = answers(locals).size
        end
      end

      # Put permanents or cards on top or bottom of their owners' libraries (CR 401.4); with
      # `position: "owner_choice"` each owner chooses top or bottom.
      class PutInLibrary < ChoiceEffect
        POSITIONS = %w[top bottom owner_choice].freeze

        primitive :effect, :put_in_library,
                  description: "Put each referenced permanent, or card in a graveyard or exile, into its owner's " \
                               "library: on the `top` or `bottom`, or (`owner_choice`) where its owner chooses.",
                  rules: %w[401.4 400.7 608.2b],
                  params: { "to" => "selector", "position" => POSITIONS.join(" | ") },
                  example: { "put_in_library" => { "to" => { "target" => 0 }, "position" => "bottom" } }

        FROM = %i[battlefield graveyard exile].freeze

        attr_reader :position

        def self.keys = %w[to position if]

        def setup(params, errors, path)
          @position = Mechanics.fetch_param(params, :position).to_s
          errors << "#{path}.position: must be one of #{POSITIONS.join(", ")}" unless POSITIONS.include?(@position)
        end

        def to_s = "put into its owner's library (#{position.tr("_", " ")}) → #{to}"

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || locals.key?("refs") || condition.nil? || condition.true?(engine, ctx)

          refs = (locals["refs"] ||= movable(engine, ctx))
          done = (locals["done"] ||= 0)
          while (id = refs[done])
            where = position
            if where == "owner_choice"
              answer = answers(locals)[done] or return ask_owner(engine, locals, id)
              where = answer["type"]
            end
            Linked.remember!(engine, ctx, id)
            engine.move!(id, :library, reason: "put", position: where.to_sym)
            locals["done"] = done += 1
          end
          :done
        end

        private

        def movable(engine, ctx)
          refs(engine, ctx).select { FROM.include?(engine.state.objects[it]&.zone) }
        end

        def ask_owner(engine, locals, id)
          obj = engine.object(id)
          ask(engine, locals, obj.owner, "Put #{engine.chars(obj).name} on the top or the bottom of your library?",
              [{ "type" => "top", "object" => id }, { "type" => "bottom", "object" => id }])
        end
      end

      # Shuffling cards into their owners' libraries (CR 701.24c): each owner shuffles their library even
      # if none of the cards is still where it was.
      class ShuffleIntoLibrary < Effect
        primitive :effect, :shuffle_into_library,
                  description: "Put each referenced card (in a graveyard or exile) or permanent into its owner's " \
                               "library; each of those owners shuffles their library.",
                  rules: %w[701.24a 701.24c],
                  params: { "to" => "selector" },
                  example: { "shuffle_into_library" => { "to" => { "target" => 0 } } }

        def self.keys = %w[to if]

        def apply(engine, ctx)
          owners = []
          refs(engine, ctx).each do |id|
            obj = engine.state.objects[id]
            next unless obj && PutInLibrary::FROM.include?(obj.zone) # abilities are on the stack, players aren't objects

            owners << obj.owner
            engine.move!(id, :library, reason: "shuffle")
          end
          owners.uniq.sort.each { engine.shuffle_library!(it) }
        end
      end

      # Shuffle a library (CR 701.24a).
      class ShuffleLibrary < Effect
        primitive :effect, :shuffle_library, description: "Each referenced player shuffles their library (default: you).",
                                             rules: %w[701.24a], params: { "to" => "selector" },
                                             example: { "shuffle_library" => {} }
        def self.keys = %w[to if]
        def self.default_to = "you"
        def apply(engine, ctx) = players(engine, ctx).each { engine.shuffle_library!(it) }
      end

      # Looking at a player's hand (CR 701.20e): the controller sees those cards; others don't.
      class LookAtHand < Effect
        primitive :effect, :look_at_hand,
                  description: "You look at each referenced player's hand (other players don't see the cards).",
                  rules: %w[701.20e], params: { "to" => "selector of players" },
                  example: { "look_at_hand" => { "to" => { "target" => 0 } } }
        def self.keys = %w[to if]
        def apply(engine, ctx) = players(engine, ctx).each { engine.look_at!(ctx.controller, it, engine.player(it).hand) }
      end
    end
  end
end
