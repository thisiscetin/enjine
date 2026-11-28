# frozen_string_literal: true

module Enjine
  class Engine
    # Room permanents (CR 709.5, CardDefinition::Rooms). Which doors are unlocked is the face the permanent has up:
    # its card is the combined card with both doors unlocked, "<id>/1" with only the left one, "<id>/2" with only
    # the right one and "<id>/3" with neither. So its name, mana cost, mana value and abilities are always those of
    # its unlocked doors (CR 709.5) with no special case elsewhere.
    #
    # A door cast as a spell (CR 709.3) is the spell's face; the permanent it becomes has that door unlocked
    # (CR 709.5d) and "when you unlock this door" triggers (CR 709.5h). A Room put onto the battlefield any other way
    # enters with both doors locked (Engine::Faces#card_after_move). Unlocking is a special action (Actions::Unlock,
    # CR 116.2m, 709.5e).
    module Rooms
      FACE_DOORS = { 0 => %w[left right], 1 => %w[left], 2 => %w[right], 3 => [] }.freeze
      DOOR_FACE = { "left" => 1, "right" => 2 }.freeze

      def room?(obj) = !obj.memory["own_card"] && catalog.fetch(obj.card).layout == "room"

      # The doors of a Room permanent that are unlocked (CR 709.5c), and those that are locked.
      def unlocked_doors(obj) = room?(obj) && obj.zone == :battlefield ? FACE_DOORS.fetch(catalog.fetch(obj.card).face_index) : []
      def locked_doors(obj) = room?(obj) && obj.zone == :battlefield ? CardDefinition::Rooms::DOORS - unlocked_doors(obj) : []

      # A door's unlock cost: its mana cost (CR 709.5e).
      def door_cost(obj, door) = catalog.fetch(obj.card).card.face(DOOR_FACE.fetch(door)).mana_cost

      # The face a Room card has when it enters the battlefield not as a resolving door spell: both doors locked
      # (CR 709.5d).
      def room_locked_face(card) = catalog.fetch(card).card.face(CardDefinition::Rooms::LOCKED_FACE).id

      # CR 116.2m, 709.5e: in a main phase of their turn with an empty stack, the player may unlock each locked door
      # of each Room they control that they can pay for.
      def unlock_options(index)
        return [] unless sorcery_timing?(index)

        state.battlefield.flat_map do |id|
          obj = object(id)
          next [] unless obj.controller == index && room?(obj)

          locked_doors(obj).filter_map do |door|
            cost = door_cost(obj, door)
            { type: "unlock", object: id, door: door } if cost && affordable?(index, cost, nil)
          end
        end
      end

      # The permanent gets that door's unlocked designation (CR 709.5c, 709.5f); "when you unlock this door" and "when
      # you fully unlock" trigger (CR 709.5h-i). `player`: who unlocked it.
      def unlock_door!(obj, door, player = obj.controller)
        return false unless locked_doors(obj).include?(door)

        open = unlocked_doors(obj) + [door]
        set_room_doors!(obj, open)
        emit Events::DoorUnlocked.new(player: name(player), object: obj.id, door: door, fully: open.size == 2)
        true
      end

      # CR 709.5g: the permanent loses that door's unlocked designation.
      def lock_door!(obj, door)
        return false unless unlocked_doors(obj).include?(door)

        set_room_doors!(obj, unlocked_doors(obj) - [door])
        emit Events::DoorLocked.new(object: obj.id, door: door)
        true
      end

      # CR 709.5d, 709.5h: the permanent a door spell became has that door unlocked, which triggers abilities.
      def room_entered!(fresh, old)
        return unless old.zone == :stack && fresh.zone == :battlefield && room?(fresh)

        door = FACE_DOORS.fetch(catalog.fetch(fresh.card).face_index)
        return unless door.size == 1

        emit Events::DoorUnlocked.new(player: name(fresh.controller), object: fresh.id, door: door.first, fully: false)
      end

      private

      def set_room_doors!(obj, open)
        index = FACE_DOORS.key(CardDefinition::Rooms::DOORS & open)
        obj.card = catalog.fetch(obj.card).card.face(index).id
      end
    end
    include Rooms
  end
end
