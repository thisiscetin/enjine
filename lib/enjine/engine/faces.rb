# frozen_string_literal: true

module Enjine
  class Engine
    # Cards with more than one face (CR 712 double-faced, 716 adventurer, 721 omen, 723 preparation cards;
    # see CardDefinition::Faces). The face that is up is the object's `card`: a face's id ("alfa/1") while
    # that face is up, the card's own id while the front face is. So every characteristic, ability and
    # copiable value (CR 707.8) comes from the face that's up with no special case.
    #
    #   memory["transformed_at"]  when the permanent last transformed (a timestamp), CR 701.27g
    #   memory["prepared"]        the id of the prepare spell copy in exile while it's prepared (CR 723.3c)
    #   memory["prepared_for"]    on that copy: the prepared permanent
    #   memory["melded"]          on a melded permanent (its object is one card of the pair, back face up): the
    #                             other card's id (CR 713.1a)
    module Faces
      ALTERNATIVE_SPELLS = %w[modal adventure omen].freeze

      # ---- reading -----------------------------------------------------------------------------

      # CR 701.27h: a double-faced permanent with its back face up.
      def transformed?(obj)
        defn = catalog.fetch(own_card(obj))
        obj.zone == :battlefield && defn.double_faced? && defn.face_index.positive?
      end

      def prepared?(obj) = obj.zone == :battlefield && obj.memory.key?("prepared")

      # The card an object is after moving to `to` (CR 400.7): its front face (CR 712.6a, 716.4, 721.4),
      # except that a spell becoming a permanent keeps the face it had on the stack (CR 712.10) and a copy
      # keeps the face it copies (CR 707.8, 716.3c, 723.3c).
      def card_after_move(old, to)
        own = own_card(old)
        return own if old.memory["copy"] || (old.zone == :stack && to == :battlefield)

        catalog.fetch(own).card.id
      end

      # ---- entering with a face up (CR 712.9, 712.11a-b) --------------------------------------------

      # Whether the card can enter the battlefield with face `index` up: it's a double-faced card and that
      # face is a permanent (CR 712.11a-b); otherwise it stays where it is.
      def can_enter_face?(obj, index)
        defn = catalog.fetch(own_card(obj)).card
        faced = defn.double_faced? || (defn.layout == "meld" && obj.memory.key?("melded")) # CR 713.1b: only melded
        faced && index < defn.faces.size && defn.face(index).permanent?
      end

      def enter_face!(fresh, index)
        fresh.card = catalog.fetch(fresh.card).card.face(index).id if can_enter_face?(fresh, index)
      end

      # The definition of the face an entering object will have up (for its own entering replacements,
      # CR 614.12), or nil when it enters as it is.
      def entering_face(obj, enters)
        index = enters && enters["face"]
        index && can_enter_face?(obj, index) ? catalog.fetch(own_card(obj)).card.face(index) : nil
      end

      # ---- transforming (CR 701.27) ---------------------------------------------------------------

      # Turns a double-faced permanent over (CR 701.27a). Nothing happens to a permanent that isn't a
      # double-faced card or token (CR 701.27d; a copy of a double-faced card is, CR 707.8a) or whose other
      # face is an instant or sorcery (CR 701.27e). It stays the same object (CR 701.27c, 712.15).
      def transform!(obj)
        own = catalog.fetch(own_card(obj))
        return false unless obj.zone == :battlefield && own.double_faced?

        into = own.other_face
        return false if into.type?(:instant) || into.type?(:sorcery)

        if obj.memory["own_card"] then obj.memory["own_card"] = into.id # still a copy of something else
        else obj.card = into.id
        end
        obj.memory["transformed_at"] = next_timestamp!
        emit Events::Transformed.new(object: obj.id, card: into.id)
        true
      end

      # CR 701.27g: an activated or triggered ability of the permanent transforms it only if it hasn't
      # transformed since the ability was put on the stack (the ability object's id is numbered then).
      def transform_still_allowed?(obj, ctx)
        ability = state.objects[ctx.object]
        return true unless ability&.ability? && ability.source == obj.id

        at = obj.memory["transformed_at"] or return true
        at < ability.id.split("#").last.to_i
      end

      # ---- meld (CR 701.42, 713) -------------------------------------------------------------------

      # CR 701.42b: two cards (not tokens or copies) of one meld pair: meld cards with the same back face name.
      def meld_pair?(one, two)
        a, b = [one, two].map { catalog.fetch(own_card(it)).card }
        [one, two].none? { token?(it) || it.memory["copy"] } && a.id != b.id && [a, b].all? { it.layout == "meld" } &&
          a.face(1).name == b.face(1).name
      end

      # CR 701.42a, 713.6: the exiled cards `first` and `second` of a meld pair enter the battlefield as one
      # permanent with the back face up, under `controller`'s control; `first`'s object stands for both. Cards
      # that can't be melded stay where they are (CR 701.42c).
      def meld!(first, second, controller)
        return unless [first, second].all? { it.zone == :exile } && meld_pair?(first, second)

        state.exile.delete(second.id)
        state.objects.delete(second.id)
        move!(first.id, :battlefield, controller: controller, reason: "meld",
                                      enters: { "face" => 1, "memory" => { "melded" => second.card } })
      end

      # CR 713.8, 713.8c: a melded permanent that leaves the battlefield puts its two cards into the new zone;
      # the other card is a new object there too, and both are the result of what moved it.
      def unmeld!(old, to, data)
        other = create_object(old.memory["melded"], old.owner, to)
        arrive!(other, old, data.merge("enters" => { "tapped" => false, "counters" => {} })) if to == :battlefield
        state.zone_list(to, old.owner).unshift(other.id)
        record_result!(other.id)
        emit Events::ZoneChanged.new(card: other.card, old_id: nil, new_id: other.id, owner: name(old.owner),
                                     from: "battlefield", to: to.to_s, reason: data["reason"])
      end

      # ---- casting another face (CR 712.8b, 716.3, 721.3) ----------------------------------------------

      # The faces other than the front a card can be cast as: a modal card's nonland faces, an Adventure, an
      # Omen. A preparation card's spell is cast only as a copy (CR 723.3).
      def alternative_faces(obj)
        defn = catalog.fetch(obj.card)
        return [] if obj.memory["copy"] || defn.face_index.positive? || !ALTERNATIVE_SPELLS.include?(defn.layout)

        (1...defn.faces.size).reject { defn.face(it).land? }
      end

      # Evaluates the block with face `index` up (CR 712.8c, 716.3a: only that face is evaluated). Nothing in
      # the block changes state.
      def with_face(obj, index)
        card = obj.card
        obj.card = catalog.fetch(obj.card).face(index).id
        yield
      ensure
        obj.card = card
      end

      # Priority options for casting the cards in `index`'s hand as another face.
      def face_cast_options(index, id)
        obj = object(id)
        alternative_faces(obj).filter_map do |face|
          { type: "cast", object: id, face: face } if with_face(obj, face) { castable?(index, id) }
        end
      end

      # CR 712.9: a modal double-faced card is played as a land with a land face up.
      def face_land_options(id)
        defn = catalog.fetch(object(id).card)
        return [] unless defn.layout == "modal" && defn.face_index.zero?

        (1...defn.faces.size).filter_map { { type: "play_land", object: id, face: it } if defn.face(it).land? }
      end

      # The spell goes on the stack with the chosen face up (CR 712.8b, 716.3b, 721.3b).
      def turn_spell_face!(obj, face)
        obj.card = catalog.fetch(obj.card).face(face).id if face
      end

      # CR 716.3d, 721.3d: a resolving Adventure is exiled (its controller may play the card while it stays
      # exiled, not as an Adventure) and a resolving Omen is shuffled into its owner's library, instead of
      # going to the graveyard. A copy isn't a card (it ceases to exist). True when handled.
      def put_away_spell_face!(obj)
        defn = catalog.fetch(obj.card)
        return false if obj.memory["copy"] || defn.face_index.zero?

        case defn.layout
        when "adventure"
          fresh = move!(obj.id, :exile, reason: "adventure")
          grant_play_permission!(obj.controller, [fresh.id], duration: "while_exiled", play: "play") if fresh&.zone == :exile
        when "omen"
          move!(obj.id, :library, reason: "omen")
          shuffle_library!(obj.owner)
        else return false
        end
        true
      end

      # ---- prepared (CR 723.3) --------------------------------------------------------------------

      # CR 723.3a, 723.3c: a permanent with a prepare spell (in its copiable values, CR 723.2b) becomes
      # prepared: its controller creates a copy of the prepare spell in exile and may cast it while the
      # permanent stays prepared. A permanent already prepared can't become prepared again.
      def prepare!(obj)
        defn = catalog.fetch(obj.card)
        return false unless obj.zone == :battlefield && !obj.memory.key?("prepared") && defn.layout == "prepare"
        return false if defn.face_index.positive?

        spell = create_card_copy!([defn.face(1).id, {}], obj.controller, :exile)
        spell.memory["prepared_for"] = obj.id
        obj.memory["prepared"] = spell.id
        grant_play_permission!(obj.controller, [spell.id], duration: "while_exiled", play: "cast")
        emit Events::PreparedChanged.new(object: obj.id, prepared: true)
        true
      end

      # CR 723.3b: it loses the designation; its copy in exile ceases to exist (Engine::Copies).
      def unprepare!(obj)
        return false unless obj.memory.delete("prepared")

        emit Events::PreparedChanged.new(object: obj.id, prepared: false)
        true
      end

      # CR 723.3c: the copy stays in exile while its permanent is on the battlefield and prepared with it.
      def prepared_copy?(obj)
        perm = obj.zone == :exile && state.objects[obj.memory["prepared_for"].to_s]
        perm ? perm.zone == :battlefield && perm.memory["prepared"] == obj.id : false
      end

      # CR 723.3c: the permanent loses the designation as its copy becomes cast (`origin`: the copy's id).
      def cast_prepared_copy!(origin)
        perm = state.battlefield.map { object(it) }.find { it.memory["prepared"] == origin } or return
        unprepare!(perm)
      end
    end
    include Faces
  end
end
