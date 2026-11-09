# frozen_string_literal: true

module Enjine
  module Mechanics
    module Effects
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
    end
  end
end
