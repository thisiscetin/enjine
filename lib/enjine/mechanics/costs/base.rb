# frozen_string_literal: true

module Enjine
  module Mechanics
    module Costs
      # Costs that need choices while casting or activating (CR 601.2h, 602.2b): which permanents to tap
      # or sacrifice, which counters to remove. Each choice is a `choose_cost` decision recorded in the
      # cast frame's "paid" list ({"cost": index, "object": id, ...}); the spell or ability keeps that list
      # (GameObject#paid) so effects can ask about "the sacrificed creature". Tapping happens at once
      # (cancelling untaps); sacrificing and removing counters happen as the spell or ability becomes cast.
      class Choosing < Primitive
        attr_reader :count, :filter

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          raw = Mechanics.fetch_param(params, :filter) || default_filter
          filter = Mechanics.build_entry(:filter, raw, errors, "#{path}.filter")
          count = Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1)
          new(filter, count, Mechanics.flag_param(params, :other, errors, path), params, errors, path)
        end

        def self.keys = %w[filter count other]
        def self.default_filter = "permanent"

        def initialize(filter, count, other, _params, _errors, _path)
          super()
          @filter = filter
          @count = count
          @other = other
          freeze
        end

        def mana? = false
        def choices_needed = count

        # Permanents the controller of `object` controls that match (not `object` itself for "another").
        def matching(engine, object)
          engine.state.battlefield.select do |id|
            perm = engine.object(id)
            perm.controller == object.controller && !(@other && id == object.id) &&
              @filter.match_for?(engine, id, object.controller, object.id)
          end
        end

        # The options still open, given the choices already made for this cost (`chosen`: paid entries).
        def choice_options(engine, object, chosen)
          taken = chosen.map { it["object"] }
          candidates(engine, object).reject { taken.include?(it) }.map { { object: it } }
        end

        def candidates(engine, object) = matching(engine, object)
        def payable?(engine, object) = candidates(engine, object).size >= count

        # Called when a choice is made: the paid entry to record (and any immediate payment).
        def choose!(_engine, option) = { "object" => option[:object] }

        # Called as the spell or ability becomes cast, with this cost's paid entries.
        def pay_chosen!(_engine, _object, _entries) = nil

        # Costs without choices of their own are paid by ActivatedAbility's finishing step.
        def pay!(_engine, _object) = nil

        def what = @filter.is_a?(Class) ? @filter.primitive_name.tr("_", " ") : @filter.to_s

        def amount_words
          if count == 1
            @other ? "another" : "a"
          else
            count.to_s
          end
        end
      end

      # `count` cards from one of your zones (`zone`) matching the card spec `card`, never the card the spell
      # or ability belongs to: "discard a card", "exile two cards from your graveyard" (CR 601.2h, 602.2b).
      class CardsCost < Choosing
        def self.keys = %w[count card]
        def self.zone = raise(NotImplementedError)

        # `count` "X": as many as the X announced for the spell or ability (CR 601.2b, 107.3a).
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          count = if Mechanics.fetch_param(params, :count) == "X" then "X"
                  else Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1)
                  end
          raw = Mechanics.fetch_param(params, :card)
          spec = raw && CardSpec.build(raw, errors, "#{path}.card")
          new(spec, count, false, params, errors, path)
        end

        def candidates(engine, object)
          engine.player(object.controller).public_send(self.class.zone).select do |id|
            id != object.id && (filter.nil? || filter.match?(engine, engine.object(id)))
          end
        end

        # "Exile X cards": the engine asks for as many as X (Engine::CastChoices#cost_chosen?); X can be at
        # most the number of matching cards (Engine::Costs#x_limit).
        def x? = count == "X"
        def choices_needed = x? ? 0 : super
        def payable?(engine, object) = x? || super
        def x_limit(engine, object) = candidates(engine, object).size

        # As it becomes cast, the chosen cards still where they were chosen are paid (exiled by default).
        def pay_chosen!(engine, _object, entries)
          entries.map { it["object"] }.select { engine.state.objects[it]&.zone == self.class.zone }.each { pay_card!(engine, it) }
        end

        def pay_card!(engine, id) = engine.move!(id, :exile, reason: "cost")

        def cards_text = "#{count == 1 ? "a" : count} #{filter || "card"}#{"s" unless count == 1}"
      end
    end
  end
end
