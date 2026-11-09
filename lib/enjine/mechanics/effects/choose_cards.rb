# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
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
          @optional = Mechanics.flag_param(params, "optional", errors, path)
          @put = Mechanics.fetch_param(params, :put).to_s
          errors << "#{path}.put: must be one of #{PUT.join(", ")}" unless PUT.include?(@put)
          @flags = %w[tapped link look].to_h { [it, Mechanics.flag_param(params, it, errors, path)] }
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
    end
  end
end
