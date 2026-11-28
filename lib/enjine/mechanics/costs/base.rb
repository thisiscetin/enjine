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
      #
      # "Exile any number of black cards from your graveyard with fifteen or more black mana symbols among their mana
      # costs" (CR 107.4, 202.1): `count: "any"` with `symbols: {"color": "B", "at_least": 15}`. The player chooses
      # cards one at a time (`choose_cost`) and may stop (`done`) once the chosen cards have enough symbols.
      class CardsCost < Choosing
        # Where cards exiled to pay a cost are remembered on the spell or ability (selector "exiled_for_cost").
        EXILED = "exiled_for_cost"

        def self.keys = %w[count card symbols]
        def self.zone = raise(NotImplementedError)

        # `count` "X": as many as the X announced for the spell or ability (CR 601.2b, 107.3a).
        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, keys, errors, path)
          count = Mechanics.fetch_param(params, :count)
          count = Mechanics.integer_param(params, :count, errors, path, default: 1, min: 1) unless %w[X any].include?(count)
          raw = Mechanics.fetch_param(params, :card)
          spec = raw && CardSpec.build(raw, errors, "#{path}.card")
          new(spec, count, false, params, errors, path)
        end

        def initialize(filter, count, other, params, errors, path)
          @symbols = symbols_param(Mechanics.fetch_param(params, :symbols), errors, path)
          errors << "#{path}.count: \"any\" needs `symbols`" if (count == "any") != !@symbols.nil?
          super
        end

        def symbols_param(raw, errors, path)
          return nil if raw.nil?

          ok = raw.is_a?(Hash) && Mana::COLORS.include?(raw["color"].to_s.upcase.to_sym) && raw["at_least"].is_a?(Integer) &&
               raw["at_least"].positive? && raw.keys.sort == %w[at_least color]
          return { "color" => raw["color"].to_s.upcase.to_sym, "at_least" => raw["at_least"] } if ok

          errors << "#{path}.symbols: must be {\"color\": W|U|B|R|G, \"at_least\": integer >= 1}"
          nil
        end

        # The card spec sees who pays (CR 201.2a: "the same name as a legendary permanent you control").
        def candidates(engine, object)
          ctx = EffectContext.new(object.controller, object.id, object.id, [])
          engine.player(object.controller).public_send(self.class.zone).select do |id|
            id != object.id && (filter.nil? || filter.match?(engine, engine.object(id), ctx))
          end
        end

        # "Exile X cards": the engine asks for as many as X (Engine::CastChoices#cost_chosen?); X can be at
        # most the number of matching cards (Engine::Costs#x_limit).
        def x? = count == "X"
        def any? = count == "any"
        def choices_needed = x? || any? ? 0 : super
        def x_limit(engine, object) = candidates(engine, object).size

        def payable?(engine, object)
          return true if x?
          return super unless any?

          symbols_among(engine, candidates(engine, object)) >= @symbols["at_least"]
        end

        # An "any number" choice remembers its card's symbols (CR 107.4e: a hybrid symbol is each of its colors).
        def choose!(engine, option)
          entry = super
          any? ? entry.merge("symbols" => symbols_among(engine, [option[:object]])) : entry
        end

        def finishable?(entries) = any? && entries.sum { it["symbols"].to_i } >= @symbols["at_least"]

        # Engine::CastChoices#cost_chosen?: "any number" is chosen once enough symbols are and the player is done.
        def chosen?(engine, object, entries, done)
          return entries.size >= choices_needed unless any?

          finishable?(entries) && (done || choice_options(engine, object, entries).empty?)
        end

        def symbols_among(engine, ids) = ids.sum { engine.chars(it).mana_cost&.symbols_of(@symbols["color"]).to_i }

        # As it becomes cast, the chosen cards still where they were chosen are paid (exiled by default).
        def pay_chosen!(engine, _object, entries)
          entries.map { it["object"] }.select { engine.state.objects[it]&.zone == self.class.zone }.each { pay_card!(engine, it) }
        end

        # An exiled card is remembered by the spell or ability being cast, or resolving for a cost paid then (CR 118.12):
        # "copy those exiled cards".
        def pay_card!(engine, id)
          fresh = engine.move!(id, :exile, reason: "cost") or return
          holder = engine.cost_holder
          (holder.memory[EXILED] ||= []) << fresh.id if holder
        end

        def cards_text
          many = { 1 => "a", "any" => "any number of" }.fetch(count, count)
          text = "#{many} #{filter || "card"}#{"s" unless count == 1}"
          @symbols ? "#{text} with #{@symbols["at_least"]} or more {#{@symbols["color"]}} symbols among their mana costs" : text
        end
      end
    end
  end
end
