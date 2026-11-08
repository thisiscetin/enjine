# frozen_string_literal: true

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
        primitive :effect, :search_library,
                  description: "Search your library for up to `count` cards matching `for`, then put them into your " \
                               "hand (or onto the battlefield, tapped if `tapped`) and shuffle. With a stated quality " \
                               "you may find fewer (or none); a search for just \"a card\" must find one if it can. " \
                               "`reveal` shows the found cards to every player.",
                  rules: %w[701.23a 701.23b 701.23d 701.23e 701.20a 701.24a 701.24b],
                  params: { "for" => "card spec: \"card\" (default), {\"types\"|\"subtypes\"|\"supertypes\": [...], " \
                                     "\"name\": \"...\"} or {\"any_of\": [spec, ...]}",
                            "count" => "integer (default 1) or \"any\" (any number)",
                            "put" => "\"hand\" (default) or \"battlefield\"",
                            "tapped" => "true: the cards enter tapped (with put: battlefield)",
                            "reveal" => "true: reveal the found cards" },
                  example: { "search_library" => { "for" => { "supertypes" => ["basic"], "types" => ["land"] },
                                                   "reveal" => true } }

        ZONES = %w[hand battlefield].freeze

        attr_reader :spec, :count, :put, :tapped, :reveal

        def self.keys = %w[for count put tapped reveal if]
        def self.default_to = "you"

        def setup(params, errors, path)
          @spec = CardSpec.build(Mechanics.fetch_param(params, :for), errors, "#{path}.for")
          @count = Mechanics.fetch_param(params, :count) || 1
          unless @count == "any" || (@count.is_a?(Integer) && @count.positive?)
            errors << "#{path}.count: must be a positive integer or \"any\""
          end
          @put = (Mechanics.fetch_param(params, :put) || "hand").to_s
          errors << "#{path}.put: must be one of #{ZONES.join(", ")}" unless ZONES.include?(@put)
          @tapped = flag(params, :tapped, errors, path)
          @reveal = flag(params, :reveal, errors, path)
          errors << "#{path}.tapped: only cards put onto the battlefield can enter tapped" if @tapped && @put != "battlefield"
        end

        def flag(params, key, errors, path)
          value = Mechanics.fetch_param(params, key)
          errors << "#{path}.#{key}: must be true or false" unless [nil, true, false].include?(value)
          value == true
        end

        def to_s
          many = count == "any" ? "any number of" : "up to #{count}"
          "search your library for #{many} #{spec}#{", reveal" if reveal} → #{put}#{" tapped" if tapped}, shuffle"
        end

        def run(engine, ctx, locals)
          return :done unless locals["asked"] || condition.nil? || condition.true?(engine, ctx)

          index = ctx.controller
          found = answers(locals).select { it["type"] == "find" }.map { it["object"] }
          unless stop?(locals, found)
            choices = candidates(engine, index, found)
            return ask(engine, locals, index, "Search your library (#{spec}): find a card", choices) unless choices.empty?
          end
          finish!(engine, index, found)
          :done
        end

        private

        def stop?(locals, found)
          answers(locals).any? { it["type"] == "done" } || (count != "any" && found.size >= count)
        end

        # One option per distinct matching card (CR 701.23a); "done" stops looking unless the
        # search is for just a quantity of cards (CR 701.23b, 701.23d).
        def candidates(engine, index, found)
          ids = (engine.player(index).library - found).sort.select { spec.match?(engine, engine.object(it)) }
          choices = ids.uniq { engine.object(it).card }.map { { "type" => "find", "object" => it } }
          return choices if choices.empty? || (spec.any? && count != "any")

          choices << { "type" => "done" }
        end

        def finish!(engine, index, found)
          if reveal && put == "hand"
            found.each do |id|
              engine.emit Events::CardRevealed.new(player: engine.name(index), object: id, card: engine.object(id).card)
            end
          end
          enters = tapped ? { "tapped" => true } : nil
          found.each { engine.move!(it, put.to_sym, reason: "search", enters: enters) }
          engine.shuffle_library!(index) # CR 701.24b: the found cards have left; the rest is shuffled
        end
      end
    end
  end
end
