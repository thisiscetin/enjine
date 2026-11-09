# frozen_string_literal: true

require_relative "library"

module Enjine
  module Mechanics
    module Effects
      # Search your library (CR 701.23), optionally reveal what was found (CR 701.20a), put it
      # into your hand or onto the battlefield, then shuffle (CR 701.24).
      #
      # The searcher picks one card at a time. Copies of the same card in a library are
      # interchangeable, so each distinct card is offered once. Only the searcher sees the
      # choices; other players see the reveal (when the effect reveals), the zone change
      # as their zone rules allow, and the shuffle.
      class SearchLibrary < ChoiceEffect
        include EntersBattlefield # effects/library.rb

        primitive :effect, :search_library,
                  description: "Search your library for up to `count` cards matching `for`, then put them into your " \
                               "hand (or onto the battlefield, tapped if `tapped`, with `counters`) and shuffle. With a " \
                               "stated quality you may find fewer (or none); a search for just \"a card\" must find one " \
                               "if it can. `reveal` shows the found cards to every player. `searcher` names another " \
                               "player who searches their own library (e.g. {\"controller_of\": {\"target\": 0}}); " \
                               "`may: true` lets the searcher decline (then nothing is shuffled).",
                  rules: %w[701.23a 701.23b 701.23d 701.23e 701.20a 701.24a 701.24b 118.12 110.2a],
                  params: { "for" => "card spec: \"card\" (default), {\"types\"|\"subtypes\"|\"supertypes\": [...], " \
                                     "\"name\": \"...\"} or {\"any_of\": [spec, ...]}",
                            "count" => "integer (default 1), \"any\" (any number) or an amount (\"up to that many\")",
                            "put" => "\"hand\" (default) or \"battlefield\"",
                            "tapped" => "true: the cards enter tapped (with put: battlefield)",
                            "counters" => "{counter name: n}: the cards enter with these counters (with put: battlefield)",
                            "reveal" => "true: reveal the found cards",
                            "searcher" => "selector of the searching player (default \"you\")",
                            "may" => "true: the searcher may choose not to search" },
                  example: { "search_library" => { "for" => { "supertypes" => ["basic"], "types" => ["land"] },
                                                   "reveal" => true } }

        ZONES = %w[hand battlefield].freeze

        attr_reader :spec, :count, :put, :tapped, :reveal

        def self.keys = %w[for count put tapped counters reveal searcher may if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          @count = parse_count(Mechanics.fetch_param(params, :count) || 1, errors, path)
          @put = (Mechanics.fetch_param(params, :put) || "hand").to_s
          errors << "#{path}.put: must be one of #{ZONES.join(", ")}" unless ZONES.include?(@put)
          @tapped = flag(params, :tapped, errors, path)
          @reveal = flag(params, :reveal, errors, path)
          @may = flag(params, :may, errors, path)
          errors << "#{path}.tapped: only cards put onto the battlefield can enter tapped" if @tapped && @put != "battlefield"
          @counters = parse_counters(Mechanics.fetch_param(params, :counters), errors, path)
          raw = Mechanics.fetch_param(params, :searcher) || "you"
          @searcher = Selector.build(raw, errors, "#{path}.searcher", targets_count: @targets_count, results_count: @results_count)
        end

        def parse_count(raw, errors, path)
          return raw if raw == "any" || (raw.is_a?(Integer) && raw.positive?)
          return Linked.amount(raw, errors, "#{path}.count", @targets_count, @results_count) if raw.is_a?(Hash)

          errors << "#{path}.count: must be a positive integer, \"any\" or an amount"
          1
        end

        def parse_counters(raw, errors, path)
          return {} if raw.nil?

          unless raw.is_a?(Hash) && raw.all? { |name, n| Counters.valid?(Counters.normalize(name.to_s)) && n.is_a?(Integer) && n.positive? }
            errors << "#{path}.counters: must be {counter name: positive integer}"
            return {}
          end
          errors << "#{path}.counters: only cards put onto the battlefield enter with counters" if @put != "battlefield"
          raw.to_h { |name, n| [Counters.normalize(name.to_s), n] }
        end

        def flag(params, key, errors, path)
          value = Mechanics.fetch_param(params, key)
          errors << "#{path}.#{key}: must be true or false" unless [nil, true, false].include?(value)
          value == true
        end

        def to_s
          many = if count == "any" then "any number of"
                 elsif count.is_a?(Integer) then "up to #{count}"
                 else "up to #{count} (computed)"
                 end
          "search your library for #{many} #{spec}#{", reveal" if reveal} → #{put}#{" tapped" if tapped}, shuffle"
        end

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || condition.nil? || condition.true?(engine, ctx)

          index = (locals["searcher"] ||= [searcher(engine, ctx)]).first
          return :done if index.nil?

          if @may && !locals["search"]
            answer = answers(locals).first or return ask(engine, locals, index, "Search your library?",
                                                         [{ "type" => "search" }, { "type" => "decline" }])
            return :done if answer["type"] == "decline"

            locals["search"] = true
          end
          found = answers(locals).select { it["type"] == "find" }.map { it["object"] }
          unless stop?(engine, ctx, locals, found)
            choices = candidates(engine, index, found)
            return ask(engine, locals, index, "Search your library (#{spec}): find a card", choices) unless choices.empty?
          end
          return :wait if entering_choices?(engine, index, locals, found)

          finish!(engine, index, found, locals)
          :done
        end

        private

        def searcher(engine, ctx) = @searcher.resolve(engine, ctx).filter_map { Filters.player_index(engine, it) }.first

        def limit(engine, ctx, locals)
          return count unless count.respond_to?(:value)

          locals["limit"] ||= count.value(engine, ctx)
        end

        def stop?(engine, ctx, locals, found)
          wanted = limit(engine, ctx, locals)
          answers(locals).any? { it["type"] == "done" } || (wanted != "any" && found.size >= wanted)
        end

        # One option per distinct matching card (CR 701.23a); "done" stops looking unless the
        # search is for just a quantity of cards (CR 701.23b, 701.23d).
        def candidates(engine, index, found)
          ids = (engine.player(index).library - found).sort.select { spec.match?(engine, engine.object(it)) }
          choices = ids.uniq { engine.object(it).card }.map { { "type" => "find", "object" => it } }
          return choices if choices.empty? || (spec.any? && count != "any")

          choices << { "type" => "done" }
        end

        def finish!(engine, index, found, locals)
          if reveal && put == "hand"
            found.each do |id|
              engine.emit Events::CardRevealed.new(player: engine.name(index), object: id, card: engine.object(id).card)
            end
          end
          enters = {}
          enters["tapped"] = true if tapped
          enters["counters"] = @counters.dup unless @counters.empty?
          put_cards!(engine, locals, found, index, reason: "search", enters: enters.empty? ? nil : enters)
          engine.shuffle_library!(index) # CR 701.24b: the found cards have left; the rest is shuffled
        end
      end
    end
  end
end
