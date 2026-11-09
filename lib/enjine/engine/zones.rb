# frozen_string_literal: true

module Enjine
  class Engine
    # Engine support for effects that move cards between hidden and public zones: looking at and
    # revealing cards (CR 701.20), putting cards on the bottom of a library (CR 401.4), cards
    # "exiled with" a source (linked abilities, CR 607.2a, 406.6) and "until" exiles (CR 610.3).
    module Zones
      # Zone changes inside the block aren't results of the running effect (CR 400.7j names only
      # what the effect's instruction moved, e.g. not "the rest" put into a graveyard).
      def unrecorded
        saved = @recorded
        @recorded = nil
        yield
      ensure
        @recorded = saved
      end

      # CR 701.20a: every player sees the card; it stays where it is (701.20b).
      def reveal!(index, ids)
        ids.each { emit Events::CardRevealed.new(player: name(index), object: it, card: object(it).card) }
      end

      # CR 701.20e: only the looking player (and the cards' owner) learn which cards they are.
      def look_at!(index, owner, ids)
        return if ids.empty?

        emit Events::LookedAt.new(player: name(index), owner: name(owner), objects: ids.dup,
                                  cards: ids.map { object(it).card })
      end

      # Puts library cards (already in `index`'s library) on its bottom, the first id highest (CR 401.4).
      # `random`: the order is randomized with the game's RNG, so replays stay deterministic.
      def put_on_bottom!(index, ids, random: false)
        return if ids.empty?

        ids = ids.dup
        state.rng.shuffle!(ids) if random
        library = player(index).library
        library.replace((library - ids) + ids)
        emit Events::LibraryReordered.new(player: name(index), top: 0, bottom: ids.size)
      end

      # CR 607.2a: cards an ability of `source` exiled, for its linked abilities ("exiled with it").
      def link_exiled!(source, id)
        obj = state.objects[source] or return
        (obj.memory[Mechanics::Linked::EXILED] ||= []) << id
      end

      # CR 610.3, 610.3c: once the source of an "exile ... until this leaves the battlefield" effect has
      # left, the cards it exiled return to the battlefield under their owners' control. A token that left
      # can't come back (CR 111.8).
      def return_exiled_until_leaves!(old)
        ids = old.memory[Mechanics::Linked::UNTIL_LEAVES] or return
        unrecorded do
          ids.each do |id|
            card = state.objects[id]
            next unless card && card.zone == :exile && !token?(card)

            move!(id, :battlefield, reason: "return")
          end
        end
      end
    end
    include Zones
  end
end
