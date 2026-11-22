# frozen_string_literal: true

module Enjine
  module Actions
    # CR 601: cast a spell from hand. Instants and flash cards at any priority; others at sorcery speed.
    # A card in another zone can be cast when a rule or effect allows it (CR 601.3): `via` names how.
    class Cast
      def self.doc
        '`{type: "cast", object: id}` — start casting a card from your hand (CR 601.2). ' \
          '`{type: "cast", object: id, via: method}` casts a card from another zone (graveyard, exile, the top ' \
          "of your library) by the permission or alternative cost `via` names, e.g. beam me up (CR 601.3, " \
          '702.196). In a Commander game `via: "command"` casts your commander from the command zone, its cost ' \
          "including the commander tax (CR 903.8). A card outside the game is named `\"outside:<card id>\"` (CR 400.11b). " \
          '`{type: "cast", object: id, face: 1}` casts another face of a card in your hand: a modal double-faced ' \
          "card's back face, an Adventure or an Omen (CR 712.8b, 716.3, 721.3). Offered only when timing " \
          "allows, targets exist and enough mana is available."
      end

      def self.options(engine, index)
        engine.player(index).hand.flat_map do |id|
          (engine.castable?(index, id) ? [{ type: "cast", object: id }] : []) + engine.face_cast_options(index, id)
        end + engine.permission_cast_options(index)
      end

      def self.perform(engine, index, option) = engine.begin_cast!(index, option[:object], via: option[:via], face: option[:face])
    end
    register("cast", Cast)

    # CR 602 / 606: activate a non-mana activated or loyalty ability of a permanent you control,
    # or an ability that functions from your hand, such as cycling (CR 113.6m, 702.29a).
    class Activate
      def self.doc
        '`{type: "activate", object: id, ability: ref}` — start activating an ability (CR 602.2), ' \
          "including planeswalker loyalty abilities (CR 606) and abilities of cards in your hand (cycling, CR 702.29)."
      end

      def self.options(engine, index)
        out = []
        engine.state.battlefield.each do |id|
          add_options(engine, index, id, out) if engine.object(id).controller == index
        end
        off_board(engine, index).each { add_options(engine, index, it, out) }
        out
      end

      # Cards whose abilities may function off the battlefield (CR 113.6b): the hand (the owner activates, CR 602.2),
      # graveyard ("exile this card from your graveyard", CR 113.6m) and exiled cards `index` owns, less those with
      # no activated ability for their zone.
      def self.off_board(engine, index)
        pl = engine.player(index)
        ids = pl.hand + pl.graveyard + engine.state.exile.select { engine.object(it).owner == index }
        engine.own_abilities_only? ? ids.reject { engine.no_activations_here?(engine.object(it)) } : ids
      end

      def self.add_options(engine, index, id, out)
        engine.chars(id).activated_abilities.each do |inst|
          out << { type: "activate", object: id, ability: inst.ref } if engine.activatable?(index, id, inst.ref)
        end
      end

      def self.perform(engine, index, option) = engine.begin_activation!(index, option[:object], option[:ability])
    end
    register("activate", Activate)
  end
end
