# frozen_string_literal: true

module Enjine
  module Mechanics
    module Triggers
      # "When ~ enters" / "Whenever a creature you control enters" (landfall: lands you control).
      # `untapped: true` is "when this land enters untapped": the status it entered with (CR 614.12).
      # `from`: only a permanent that entered from that zone ("enters from exile", CR 603.6a).
      class Enters < Trigger
        FROM = %w[hand graveyard exile library stack outside].freeze

        primitive :trigger, :enters,
                  description: "The subject enters the battlefield. `untapped: true`: only if it entered untapped. " \
                               "`from`: only if it entered from that zone (\"enters from exile\").",
                  rules: %w[603.6a 603.2 614.12],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": you|opponent|any, \"other\": true}",
                            "untapped" => "true | false", "from" => FROM.join(" | ") },
                  example: { "enters" => { "subject" => { "each" => "land", "controller" => "you" } } }

        def self.keys = %w[subject untapped from]
        def event_class = Events::ZoneChanged

        def setup(params, errors, path)
          @untapped = params.fetch("untapped", false)
          errors << "#{path}.untapped: must be true or false" unless [true, false].include?(@untapped)
          @from = params["from"]
          errors << "#{path}.from: must be one of #{FROM.join(", ")}" unless @from.nil? || FROM.include?(@from)
        end

        def match?(engine, event, source)
          return false unless event.to == "battlefield" && (@from.nil? || event.from == @from)

          obj = engine.state.objects[event.new_id] or return false
          return false if @untapped && obj.tapped

          @subject.match?(engine, event.new_id, obj.controller, event.card, source, types: engine.chars(obj).types)
        end

        def to_s = "When #{@subject} enters#{" untapped" if @untapped}#{" from #{@from}" if @from}"
      end

      # "Whenever you play a land" (CR 305.1): a player plays a land, from their hand or, when an effect allows it,
      # from another zone (`from` / `not_from`: "from exile", "from anywhere other than your hand"). Putting a land
      # onto the battlefield with an effect isn't playing it.
      class PlaysLand < PlayerTrigger
        primitive :trigger, :plays_land,
                  description: "A player (`controller`: you (default) | opponent | any) plays a land. `from` / " \
                               "`not_from`: only a land played from (not from) that zone: hand | graveyard | exile | " \
                               "library | outside. Lands put onto the battlefield by effects aren't played.",
                  rules: %w[305.1 603.2 601.2a],
                  params: { "controller" => PLAYERS.join(" | "), "from" => "zone", "not_from" => "zone" },
                  example: { "plays_land" => { "not_from" => "hand" } }

        def self.keys = %w[controller from not_from]
        def event_class = Events::ZoneChanged

        def setup(params, errors, path)
          super
          @zones = CastFrom.build(params, errors, path)
        end

        def match?(engine, event, source)
          return false unless event.reason == "play_land" && event.to == "battlefield" && @zones.match?(event.from)

          player = engine.state.objects[event.new_id]&.controller || engine.names.index(event.owner)
          player_ok?(engine, engine.name(player), source)
        end

        def to_s = "Whenever #{who} play#{"s" unless @controller == "you"} a land#{@zones}"
      end

      # "When ~ dies" / "Whenever another creature you control dies".
      class Dies < Trigger
        primitive :trigger, :dies,
                  description: "The subject is put into a graveyard from the battlefield. Looks back in time (CR 603.10a).",
                  rules: %w[603.6c 603.10a 700.4],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, ...}" },
                  example: { "dies" => { "subject" => "self" } }

        def event_class = Events::ZoneChanged
        def leaves_battlefield? = true

        def match?(engine, event, source)
          return false unless event.from == "battlefield" && event.to == "graveyard"

          lki = engine.last_known(event.old_id) or return false
          @subject.match?(engine, event.old_id, lki["controller"], event.card, source, types: lki["types"])
        end

        def to_s = "When #{@subject} dies"
      end

      # "When ~ leaves the battlefield" / "Whenever another creature you control leaves the battlefield"
      # (CR 603.6c): a permanent moves from the battlefield to any other zone (`to`: only that zone). It
      # looks back in time (CR 603.10a): the permanent is matched as it last existed, and its own ability
      # triggers although it has left.
      class LeavesBattlefield < Trigger
        ZONES = %w[graveyard exile hand library].freeze

        primitive :trigger, :leaves_battlefield,
                  description: "The subject leaves the battlefield (for any zone, or only `to` that zone). Looks back " \
                               "in time: the permanent is matched as it last existed (types, controller, counters).",
                  rules: %w[603.6c 603.10a 400.7],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": ..., \"other\": true}",
                            "to" => ZONES.join(" | ") },
                  example: { "leaves_battlefield" => { "subject" => { "each" => "creature", "controller" => "you",
                                                                      "other" => true } } }

        def self.keys = %w[subject to]
        def event_class = Events::ZoneChanged
        def leaves_battlefield? = true

        def setup(params, errors, path)
          @to = params["to"]
          errors << "#{path}.to: must be one of #{ZONES.join(", ")}" unless @to.nil? || ZONES.include?(@to)
        end

        def match?(engine, event, source)
          return false unless event.from == "battlefield" && (@to.nil? || event.to == @to)

          lki = engine.last_known(event.old_id) or return false
          @subject.match?(engine, event.old_id, lki["controller"], event.card, source, types: lki["types"])
        end

        def to_s
          return "When #{@subject} leaves the battlefield" unless @to

          "When #{@subject} is put into #{"a " unless @to == "exile"}#{@to} from the battlefield"
        end
      end

      # "Whenever you sacrifice another permanent" / "a Food" (CR 701.21a): only its controller can sacrifice
      # a permanent, so the subject's `controller` is who sacrificed it. Looks back in time (CR 603.10a).
      class Sacrifices < Trigger
        include Batched

        primitive :trigger, :sacrifices,
                  description: "The subject is sacrificed (`controller` of the subject: who sacrificed it). Looks back " \
                               "in time, like leaves_battlefield. `batched: true`: \"one or more\", once per event batch.",
                  rules: %w[701.21a 603.10a 603.2c],
                  params: { "subject" => "\"self\" (default) or {\"each\": filter, \"controller\": you, \"other\": true}",
                            "batched" => "true | false" },
                  example: { "sacrifices" => { "subject" => { "each" => "artifact", "controller" => "you" } } }

        def self.keys = %w[subject batched]
        def event_class = Events::ZoneChanged
        def leaves_battlefield? = true
        def setup(params, errors, path) = setup_batched(params, errors, path)

        def match?(engine, event, source)
          return false unless event.from == "battlefield" && event.reason == "sacrifice"

          lki = engine.last_known(event.old_id) or return false
          @subject.match?(engine, event.old_id, lki["controller"], event.card, source, types: lki["types"])
        end

        def to_s = "Whenever #{@subject} is sacrificed"
      end

      # "Whenever one or more creature cards are put into your graveyard from anywhere" / "cards are put into
      # exile from graveyards and/or the battlefield". `controller`: whose graveyard or exile, i.e. the card's
      # owner. CR 603.6c: a "from anywhere" trigger is never a leaves-the-battlefield ability.
      class PutInto < PlayerTrigger
        include Batched
        include CardMatch

        ZONES = %w[graveyard exile].freeze
        FROM = %w[battlefield graveyard hand library stack exile].freeze

        primitive :trigger, :put_into,
                  description: "A card is put into `zone` (graveyard | exile) from anywhere, or only `from` the listed " \
                               "zones. `controller`: the card's owner (you (default) | opponent | any); optional `card` " \
                               "filter on the card. `batched: true`: \"one or more cards\", once per event batch. With " \
                               "\"battlefield\" among `from` it looks back in time like leaves_battlefield.",
                  rules: %w[603.6c 603.2c 400.3],
                  params: { "zone" => ZONES.join(" | "), "from" => "list of #{FROM.join(", ")} (default: anywhere)",
                            "controller" => PLAYERS.join(" | "), "card" => "card filter", "batched" => "true | false" },
                  example: { "put_into" => { "zone" => "graveyard", "card" => "creature", "batched" => true } }

        def self.keys = %w[zone from controller card batched]
        def event_class = Events::ZoneChanged
        # CR 603.6c: "put into a graveyard from the battlefield" is a leaves-the-battlefield ability; "from anywhere"
        # never is.
        def leaves_battlefield? = @from&.include?("battlefield") || false

        def setup(params, errors, path)
          super
          setup_batched(params, errors, path)
          setup_card(params, errors, path)
          @zone = params["zone"]
          errors << "#{path}.zone: must be one of #{ZONES.join(", ")}" unless ZONES.include?(@zone)
          @from = params["from"]
          return if @from.nil? || (@from.is_a?(Array) && !@from.empty? && (@from - FROM).empty?)

          errors << "#{path}.from: must be a list of #{FROM.join(", ")}"
        end

        def match?(engine, event, source)
          event.to == @zone && (@from.nil? || @from.include?(event.from)) && player_ok?(engine, event.owner, source) &&
            card_ok?(engine, event.card)
        end

        def to_s
          into = @zone == "exile" ? "exile" : "#{{ "you" => "your", "opponent" => "an opponent's" }.fetch(@controller, "a")} graveyard"
          from = @from ? " from #{@from.join(" or ")}" : " from anywhere"
          "Whenever #{@batched ? "one or more #{card_words}s are" : "a #{card_words} is"} put into #{into}#{from}"
        end
      end

      # "Whenever a card leaves your graveyard" / "whenever one or more cards leave your graveyard" (`batched`).
      # Looks back in time (CR 603.10a): the card is matched as it was in the graveyard.
      class LeavesGraveyard < PlayerTrigger
        primitive :trigger, :leaves_graveyard,
                  description: "A card leaves a graveyard (whose: `controller` you (default) | opponent | any). Optional " \
                               "`card` filter on its card types. `batched: true` is \"one or more cards leave\": once per " \
                               "event that moves cards (one effect, cost or action), however many cards.",
                  rules: %w[603.10a 603.2c 404.1],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card type filter, e.g. \"creature\"",
                            "batched" => "true | false" },
                  example: { "leaves_graveyard" => { "controller" => "you", "batched" => true } }

        def self.keys = %w[controller card batched]
        def event_class = Events::ZoneChanged
        def batched? = @batched

        def setup(params, errors, path)
          super
          @batched = params.fetch("batched", false)
          errors << "#{path}.batched: must be true or false" unless [true, false].include?(@batched)
          @card = params["card"] && Mechanics.build_entry(:filter, params["card"], errors, "#{path}.card")
        end

        def match?(engine, event, source)
          return false unless event.from == "graveyard" && player_ok?(engine, event.owner, source)
          return true unless @card

          defn = engine.catalog.fetch(event.card)
          @card.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def to_s
          what = @card ? Triggers.filter_words(@card) : "card"
          whose = { "you" => "your", "opponent" => "an opponent's" }.fetch(@controller, "a")
          "Whenever #{@batched ? "one or more #{what}s leave" : "a #{what} leaves"} #{whose} graveyard"
        end
      end
    end
  end
end
