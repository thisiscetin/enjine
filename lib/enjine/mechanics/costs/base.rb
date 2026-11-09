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
          other = Mechanics.fetch_param(params, :other)
          errors << "#{path}.other: must be true or false" unless [nil, true, false].include?(other)
          new(filter, count, other == true, params, errors, path)
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
    end
  end
end
