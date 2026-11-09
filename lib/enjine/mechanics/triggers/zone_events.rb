# frozen_string_literal: true

require_relative "triggers"
require_relative "events"

module Enjine
  module Mechanics
    module Triggers
      # A `batched` flag: "one or more ..." triggers once per event batch (CR 603.2c), and its "that many"
      # ({"triggering": "amount"}) is how many occurrences the batch had (Engine::Triggering#queue_trigger).
      module Batched
        def setup_batched(params, errors, path)
          @batched = params.fetch("batched", false)
          errors << "#{path}.batched: must be true or false" unless [true, false].include?(@batched)
        end

        def batched? = @batched
      end

      # Matching a card (not a permanent) by its printed characteristics.
      module CardMatch
        def setup_card(params, errors, path)
          @card = params["card"] && Mechanics.build_entry(:filter, params["card"], errors, "#{path}.card")
        end

        def card_ok?(engine, card)
          return true unless @card

          defn = engine.catalog.fetch(card)
          @card.matches_facts?(Filters::Facts.new(chars: defn.printed_characteristics, counters: {}, token: defn.token?))
        end

        def card_words = @card ? Triggers.filter_words(@card) : "card"
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

      # "Whenever you discard a card" / "one or more cards" (CR 701.9a). A cycled card is discarded too
      # (CR 702.29d).
      class Discards < PlayerTrigger
        include Batched
        include CardMatch

        primitive :trigger, :discards,
                  description: "A player (`controller`: you (default) | opponent | any) discards a card (optional `card` " \
                               "filter). `batched: true`: \"one or more cards\", once per event batch; then \"that many\" " \
                               "is how many were discarded.",
                  rules: %w[701.9a 603.2c 702.29d],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card filter", "batched" => "true | false" },
                  example: { "discards" => { "controller" => "you", "batched" => true } }

        def self.keys = %w[controller card batched]
        def event_class = Events::ZoneChanged

        def setup(params, errors, path)
          super
          setup_batched(params, errors, path)
          setup_card(params, errors, path)
        end

        def match?(engine, event, source)
          event.reason == "discard" && event.from == "hand" && player_ok?(engine, event.owner, source) && card_ok?(engine, event.card)
        end

        def to_s
          "Whenever #{who} discard#{"s" unless @controller == "you"} #{@batched ? "one or more #{card_words}s" : "a #{card_words}"}"
        end
      end

      # "Whenever you cycle a card" (CR 702.29a): a player activates a cycling (or typecycling) ability.
      class Cycles < PlayerTrigger
        include CardMatch

        primitive :trigger, :cycles,
                  description: "A player (`controller`: you (default) | opponent | any) cycles a card (activates its " \
                               "cycling or typecycling ability; optional `card` filter).",
                  rules: %w[702.29a 702.29e],
                  params: { "controller" => PLAYERS.join(" | "), "card" => "card filter" },
                  example: { "cycles" => { "controller" => "you" } }

        def self.keys = %w[controller card]
        def event_class = Events::AbilityActivated

        def setup(params, errors, path)
          super
          setup_card(params, errors, path)
        end

        def match?(engine, event, source)
          ability = engine.catalog.fetch(event.card).ability(event.ability)
          ability.respond_to?(:cycling?) && ability.cycling? && player_ok?(engine, event.player, source) &&
            card_ok?(engine, event.card)
        end

        def to_s = "Whenever #{who} cycle#{"s" unless @controller == "you"} a #{card_words}"
      end

      # "Whenever you scry" / "Whenever you surveil" (CR 701.22, 701.25): once the whole action is done
      # (CR 701.25d); scry 0 / surveil 0 isn't one (CR 701.22b, 701.25c). "Whenever you scry or surveil" is
      # `any_of` both.
      class KeywordActionTrigger < PlayerTrigger
        def event_class = Events::KeywordAction
        def match?(engine, event, source) = event.action == self.class.action && player_ok?(engine, event.player, source)
        def to_s = "Whenever #{who} #{self.class.action}#{"s" unless @controller == "you"}"
      end

      # "Whenever you scry".
      class Scries < KeywordActionTrigger
        primitive :trigger, :scries,
                  description: "A player (`controller`: you (default) | opponent | any) scries (not scry 0). Triggers " \
                               "after the scry is complete.",
                  rules: %w[701.22a 701.22b],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "any_of" => [{ "scries" => {} }, { "surveils" => {} }] }

        def self.action = "scry"
      end

      # "Whenever you surveil".
      class Surveils < KeywordActionTrigger
        primitive :trigger, :surveils,
                  description: "A player (`controller`: you (default) | opponent | any) surveils (not surveil 0). " \
                               "Triggers after the surveil is complete.",
                  rules: %w[701.25a 701.25c 701.25d],
                  params: { "controller" => PLAYERS.join(" | ") },
                  example: { "surveils" => { "controller" => "you" } }

        def self.action = "surveil"
      end

      # "Whenever ~ becomes untapped" (CR 603.2e): not a permanent that enters untapped.
      class BecomesUntapped < Trigger
        primitive :trigger, :becomes_untapped,
                  description: "The subject becomes untapped (in the untap step or by an effect). A permanent that " \
                               "enters untapped doesn't become untapped.",
                  rules: %w[603.2e 701.26b],
                  params: { "subject" => "\"self\" (default), \"attached\" or {\"each\": filter, ...}" },
                  example: { "becomes_untapped" => { "subject" => "attached" } }

        def event_class = Events::Untapped

        def match?(engine, event, source)
          obj = engine.state.objects[event.object] or return false
          @subject.match?(engine, event.object, obj.controller, obj.card, source, types: engine.chars(obj).types)
        end

        def to_s = "Whenever #{@subject} becomes untapped"
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
                               "filter on the card. `batched: true`: \"one or more cards\", once per event batch.",
                  rules: %w[603.6c 603.2c 400.3],
                  params: { "zone" => ZONES.join(" | "), "from" => "list of #{FROM.join(", ")} (default: anywhere)",
                            "controller" => PLAYERS.join(" | "), "card" => "card filter", "batched" => "true | false" },
                  example: { "put_into" => { "zone" => "graveyard", "card" => "creature", "batched" => true } }

        def self.keys = %w[zone from controller card batched]
        def event_class = Events::ZoneChanged

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
    end
  end
end
