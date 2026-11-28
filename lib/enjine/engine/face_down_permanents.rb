# frozen_string_literal: true

module Enjine
  class Engine
    # Face-down spells and permanents (CR 708): manifested (CR 701.40), cloaked (CR 701.58), and cast face down with
    # morph (CR 702.37) or disguise (CR 702.168). The object's `card` names its face-down characteristics
    # (CardDefinition::FaceDownCards: a nameless 2/2 creature, with ward {2} for cloak and disguise) and they are its
    # copiable values (CR 708.2), so every rule reads them with no special case; the card it really is waits in
    # its memory:
    #
    #   memory["face_down_card"]  the card's own id (Engine::Copies#own_card reads it)
    #   memory["face_down_as"]    "manifest" | "cloak" | "morph" | "disguise": what made it face down
    #   memory["turned_face_up"]  the turn it was turned face up (it's the same object, CR 708.8)
    #
    # Its id doesn't name the card (Engine::FACE_DOWN_ID, like a card exiled face down). Only its controller may
    # look at it (CR 708.5, View and Events::ZoneChanged); it is revealed as it leaves the battlefield or the stack
    # for anywhere but the battlefield, and at the end of the game (CR 708.9).
    module FaceDownPermanents
      AS = { "manifest" => CardDefinition::FaceDownCards::PLAIN, "cloak" => CardDefinition::FaceDownCards::WARD,
             "morph" => CardDefinition::FaceDownCards::PLAIN, "disguise" => CardDefinition::FaceDownCards::WARD }.freeze

      def face_down_object?(obj) = obj.memory.key?("face_down_card")

      # CR 708.5: you may look at a face-down spell or permanent you control.
      def sees_face_down?(obj, index) = !face_down_object?(obj) || obj.controller == index

      # CR 701.40a, 701.58a, 702.37c, 702.168b: it becomes a face-down 2/2 (with ward {2} for cloak and disguise).
      def turn_face_down!(obj, kind)
        obj.memory["face_down_card"] = obj.card
        obj.memory["face_down_as"] = kind
        obj.card = AS.fetch(kind)
      end

      # The ways `obj` (a face-down permanent) can be turned face up now and their costs (CR 701.40b-d, 701.58b-d,
      # 702.37e, 702.168d): "mana_cost" for a manifested or cloaked creature card with a mana cost, and its own
      # "morph" / "disguise" cost (whatever made it face down).
      def face_up_costs(obj)
        return {} unless face_down_object?(obj) && obj.zone == :battlefield

        real = catalog.fetch(obj.memory["face_down_card"])
        costs = {}
        costs["mana_cost"] = real.mana_cost if %w[manifest cloak].include?(obj.memory["face_down_as"]) && real.creature? && real.mana_cost
        real.ability_instances.each do |inst|
          ability = inst.ability
          costs[ability.keyword] ||= ability.face_up_cost if ability.respond_to?(:face_up_cost) && ability.face_up_cost
        end
        costs
      end

      # CR 116.2b: any time they have priority, a player may turn a face-down permanent they control face up.
      def face_up_options(index)
        state.battlefield.flat_map do |id|
          obj = object(id)
          next [] unless obj.controller == index && face_down_object?(obj)

          face_up_costs(obj).filter_map { |via, cost| { type: "turn_face_up", object: id, via: via } if affordable?(index, cost, nil) }
        end
      end

      # CR 708.8: its copiable values become its card's; effects that applied to it still apply, and abilities about
      # entering the battlefield don't trigger. An instant or sorcery card is revealed and stays face down
      # (CR 701.40g, 701.58g).
      def turn_face_up!(obj, index = obj.controller)
        return false unless face_down_object?(obj) && obj.zone == :battlefield

        real = obj.memory["face_down_card"]
        defn = catalog.fetch(real)
        if defn.type?(:instant) || defn.type?(:sorcery)
          emit Events::CardRevealed.new(player: name(index), object: obj.id, card: real)
          return false
        end
        obj.card = obj.memory.delete("face_down_card")
        obj.memory.delete("face_down_as")
        obj.memory["turned_face_up"] = state.turn
        emit Events::TurnedFaceUp.new(player: name(index), object: obj.id, card: real)
        true
      end

      # CR 701.40a, 701.58a, 701.40f: the top card of `index`'s library is put onto the battlefield face down under
      # their control. Returns the new permanent, or nil.
      def manifest!(index, kind = "manifest", id = player(index).library.first)
        return nil unless id

        fresh = move!(id, :battlefield, reason: kind, controller: index, face_down_as: kind)
        fresh&.zone == :battlefield ? fresh : nil
      end

      # CR 708.9: what was face down is revealed to all as it leaves the battlefield (or the stack) for a zone
      # where it isn't public.
      def reveal_face_down_left!(old, fresh)
        return unless face_down_object?(old) && %i[hand library].include?(fresh.zone)

        emit Events::CardRevealed.new(player: name(old.owner), object: fresh.id, card: fresh.card)
      end

      # CR 708.9: at the end of the game every face-down permanent and spell is revealed to all.
      def reveal_face_down_at_end!
        (state.battlefield + state.stack).each do |id|
          obj = state.objects[id]
          next unless obj && face_down_object?(obj)

          emit Events::CardRevealed.new(player: name(obj.owner), object: id, card: obj.memory["face_down_card"])
        end
      end
    end
    include FaceDownPermanents
  end
end
