# frozen_string_literal: true

module Enjine
  class CardDefinition
    # Room cards: split cards with a shared type line (CR 709.5), written as
    #
    #   {"name": "Left // Right", "layout": "room", "faces": [{...left door...}, {...right door...}]}
    #
    # where each door is a card block with its own name, mana cost and abilities and the same types, supertypes
    # and subtypes (the shared type line, CR 709.5a). The card's own definition (faces[0]) has both halves
    # combined: every zone but the stack sees that (CR 709.4, 709.4b: the mana costs combined). The other faces
    # stand for the permanent's unlocked designations (CR 709.5, 709.5c): faces[1] only the left door unlocked
    # (only its name, mana cost and text), faces[2] only the right door, faces[3] both doors locked (no name, mana
    # cost or text, only the type line). With both doors unlocked a Room permanent is the combined card. A door
    # cast as a spell has only that door (CR 709.3b), so the spell is faces[1] or faces[2] (Engine::Rooms).
    #
    # "When you unlock this door" (trigger `unlocks_door`) written on a door without `door` is about that door:
    # it is tagged "left" or "right" as the card is read.
    module Rooms
      DOORS = %w[left right].freeze
      LOCKED_FACE = 3

      module_function

      # The fully locked face (CR 709.5: neither unlocked designation): no name.
      def locked_face?(face, card) = face[1] == LOCKED_FACE && face[0].layout == "room" && card["name"] == ""

      # "When you unlock this door": the door's own unlock triggers name it.
      def tag_doors(value, door)
        case value
        when Hash
          value.to_h do |key, inner|
            if key.to_s == "unlocks_door" && inner.is_a?(Hash) && !inner.key?("door")
              [key, inner.merge("door" => door)]
            else
              [key, tag_doors(inner, door)]
            end
          end
        when Array then value.map { tag_doors(it, door) }
        else value
        end
      end

      # The two halves combined (CR 709.4, 709.4b-c): both names, the mana costs added up, every ability.
      def combined(left, right)
        card = left.slice("types", "supertypes", "subtypes")
        card["name"] = "#{left["name"]} // #{right["name"]}"
        cost = [left, right].filter_map { it["mana_cost"] if it["mana_cost"].is_a?(String) }.join
        card["mana_cost"] = cost unless cost.empty?
        %w[keywords abilities colors].each do |key|
          list = [left, right].flat_map { it[key].is_a?(Array) ? it[key] : [] }
          card[key] = key == "abilities" ? list : list.uniq unless list.empty?
        end
        card
      end

      def locked(left) = left.slice("types", "supertypes", "subtypes").merge("name" => "")
    end

    private

    def read_room(card, left, right, errors, token_id)
      left, right = [left, right].zip(Rooms::DOORS).map { |door, side| Rooms.tag_doors(door, side) }
      scratch = []
      read_card(Rooms.combined(left, right), scratch, token_id)
      door_errors = %w[faces[0] faces[1]].map { prefixed(errors, it) }
      doors = [left, right].each_with_index.map { |door, i| CardDefinition.new(door, door_errors[i], face: [self, i + 1]) }
      locked = CardDefinition.new(Rooms.locked(left), scratch, face: [self, Rooms::LOCKED_FACE])
      @faces = [self, *doors, locked].freeze
      validate_room(card, doors, errors)
      scratch.each { errors << "faces: #{it}" } if errors.empty? # what only the combination gets wrong
      @source = deep_freeze({ "name" => full_name, "layout" => "room", "faces" => doors.map(&:to_h) })
    end

    # CR 709.5, 709.5a: one shared type line, on a permanent card.
    def validate_room(card, doors, errors)
      name = card["name"]
      errors << "name: must be #{full_name.inspect} (the doors' names joined by \" // \")" unless name.nil? || name == full_name
      left, right = doors
      unless %i[types supertypes subtypes].all? { left.public_send(it) == right.public_send(it) }
        errors << "faces[1].types: a Room's doors share one type line (types, supertypes, subtypes, CR 709.5a)"
      end
      errors << "faces[0].types: a Room is a permanent card (CR 709.5)" unless left.permanent?
    end
  end
end
