# frozen_string_literal: true

module Enjine
  module Actions
    # CR 601: cast a spell from hand. Instants and flash cards at any priority; others at sorcery speed.
    class Cast
      def self.doc
        '`{type: "cast", object: id}` — start casting a card from your hand (CR 601.2). ' \
          "Offered only when timing allows, targets exist and enough mana is available."
      end

      def self.options(engine, index)
        engine.player(index).hand.filter_map { |id| { type: "cast", object: id } if engine.castable?(index, id) }
      end

      def self.perform(engine, index, option) = engine.begin_cast!(index, option[:object])
    end
    register("cast", Cast)

    # CR 602 / 606: activate a non-mana activated or loyalty ability of a permanent you control.
    class Activate
      def self.doc
        '`{type: "activate", object: id, ability: ref}` — start activating an ability (CR 602.2), ' \
          "including planeswalker loyalty abilities (CR 606)."
      end

      def self.options(engine, index)
        out = []
        engine.state.battlefield.each do |id|
          obj = engine.object(id)
          next unless obj.controller == index

          engine.chars(obj).activated_abilities.each do |inst|
            out << { type: "activate", object: id, ability: inst.ref } if engine.activatable?(index, id, inst.ref)
          end
        end
        out
      end

      def self.perform(engine, index, option) = engine.begin_activation!(index, option[:object], option[:ability])
    end
    register("activate", Activate)
  end
end
