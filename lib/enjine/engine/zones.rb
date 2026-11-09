# frozen_string_literal: true

module Enjine
  class Engine
    # Objects and zones (CR 400): creating objects, moving them between zones through replacement
    # effects (CR 614), tokens, drawing, shuffling and tapping; looking at and revealing cards
    # (CR 701.20), putting cards on the bottom of a library (CR 401.4), cards "exiled with" a source
    # (linked abilities, CR 607.2a, 406.6) and "until" exiles (CR 610.3).
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

      # ---- objects & zones (CR 400) ------------------------------------------

      # A card exiled face down gets an id that doesn't name it (CR 406.3); a card's id names its front face.
      def create_object(card, owner, zone, hidden: false)
        id = "#{hidden ? FACE_DOWN_ID : card.split(CardDefinition::FACE_SEPARATOR).first}##{state.next_id}"
        state.next_id += 1
        state.objects[id] = GameObject.new(id: id, card: card, owner: owner, controller: owner, zone: zone,
                                           tapped: false, controlled_since: nil, kind: "card", counters: {},
                                           damage: 0, source: nil, ability: nil, targets: nil, loyalty_turn: nil,
                                           deathtouched: false, modes: nil, memory: {}, attached_to: nil)
      end

      # Moves an object to a zone as a new object (CR 400.7). Returns the new object.
      # Proposes a state change, lets replacement effects modify it (CR 614), and returns
      # the final proposal for the caller to execute.
      # `applied`: replacement effects that already modified the event this one replaces (CR 614.5).
      def propose(kind, data, applied = []) = Replacements.apply(self, Proposal.new(kind, data, applied.dup))

      # `face_down`: exile it face down (CR 406.3); the list of player indices who may look at it.
      def move!(id, to, reason:, position: :top, controller: nil, enters: nil, face_down: nil)
        data = plan_move(id, to, reason: reason, position: position, controller: controller, enters: enters,
                                 face_down: face_down)
        data && execute_zone_change!(data)
      end

      # The zone change `move!` would make, after replacement effects (CR 614), not yet executed; nil if a
      # replacement cancelled it. Planning several before executing any lets them happen at once (CR 614.12).
      def plan_move(id, to, reason:, position: :top, controller: nil, enters: nil, face_down: nil)
        data = { "object" => id, "to" => to, "position" => position, "reason" => reason, "controller" => controller }
        data["face_down"] = face_down if face_down && to == :exile
        data["enters"] = { "tapped" => enters&.fetch("tapped", false) == true, "counters" => {} } if to == :battlefield
        data["enters"]["face"] = enters["face"] if data["enters"] && enters&.key?("face") # seen by its own replacements
        data = propose("zone_change", data).data
        return nil if data["cancelled"] # e.g. a shield counter instead of being destroyed (CR 122.1c)

        merge_enters!(data["enters"], enters.except("tapped")) if enters && data["enters"] # tapped: replaceable (614.12)
        data
      end

      # Takes the object out of its zone; returns its last known information if it was a permanent.
      def depart!(old)
        lki = old.zone == :battlefield ? last_known_info(old) : nil # before it leaves (CR 603.10a)
        remember_last_known!(old.id, lki) if lki # CR 608.2h (see Engine::TurnHistory)
        state.zone_list(old.zone, old.owner).delete(old.id)
        state.objects.delete(old.id)
        lki
      end

      def execute_zone_change!(data)
        id = data["object"]
        to = data["to"]
        old = object(id)
        lki = depart!(old)
        face_down = to == :exile ? data["face_down"] : nil
        fresh = create_object(card_after_move(old, to), old.owner, to, hidden: !face_down.nil?) # front face up (Engine::Faces)
        carry_copy_status!(fresh, old, to) # a token or copy stays one (Engine::Copies)
        if old.zone == :battlefield
          leave_combat!(id)
          end_while_source_effects!(id) # CR 611.2b
        end
        arrive!(fresh, old, data)
        fresh.memory.merge!("face_down" => true, "may_look" => face_down.uniq.sort) if face_down
        list = state.zone_list(to, old.owner)
        data["position"] == :bottom ? list.push(fresh.id) : list.unshift(fresh.id)
        record_result!(fresh.id)
        event = Events::ZoneChanged.new(card: old.card, old_id: id, new_id: fresh.id, owner: name(old.owner),
                                        from: old.zone.to_s, to: to.to_s, reason: data["reason"],
                                        lookers: face_down&.map { name(it) })
        lki ? with_last_known(id, lki) { emit event } : emit(event)
        return_exiled_until_leaves!(old) if lki # CR 610.3
        unmeld!(old, to, data) if old.memory["melded"] # CR 713.8 (Engine::Faces)
        prepare!(fresh) if to == :battlefield && data["enters"]["prepared"] # "enters prepared" (CR 723.3a)
        fresh
      end

      # Status of the new object in its new zone (CR 110.2, 614.12 entering status).
      def arrive!(fresh, old, data)
        case data["to"]
        when :battlefield
          fresh.controller = data["controller"] || old.owner
          fresh.controlled_since = state.turn
          fresh.memory["entered"] = state.turn # "if it entered this turn" (power-up, CR 702.193a)
          fresh.memory["cast"] = true if data["enters"]["cast"] # CR 400.7d: it remembers it was cast
          fresh.memory.merge!(data["enters"]["memory"]) if data["enters"]["memory"] # CR 614.12: an "as this enters" choice
          enter_face!(fresh, data["enters"]["face"]) if data["enters"]["face"] # CR 712.9, 712.11a (Engine::Faces)
          enter_as_copy!(fresh, data["enters"]["copy"]) if data["enters"]["copy"] # CR 707.5 (Engine::Copies)
          fresh.tapped = data["enters"]["tapped"]
          fresh.counters.merge!(data["enters"]["counters"])
          carry_from_stack!(fresh, old) if old.zone == :stack
          fresh.attached_to = data["enters"]["attached_to"] # CR 608.3c: an Aura enters attached
          enter_attacking!(fresh, data["enters"]["attacking"]) if data["enters"]["attacking"] # CR 508.4, 506.3a
        when :stack
          fresh.controller = data["controller"] || old.owner
        end
      end

      # A permanent spell becoming a permanent remembers how it was cast (CR 400.7d): its X (its ETB abilities
      # use the spell's X, CR 107.3m), that it was kicked (CR 702.33d) and the mana spent to cast it (CR 601.2h).
      def carry_from_stack!(fresh, old)
        fresh.x = old.x
        fresh.memory.merge!(old.memory.slice("kicked", "kicked_with"))
        fresh.mana_spent = old.mana_spent&.dup
      end

      # CR 111.1: a token enters the battlefield under its creator's control. Entering replacement
      # effects apply to it like to any permanent (CR 614.1c, 614.12).
      # `memory`: a token that's a copy (Engine::Copies#create_token_copy!).
      # A replacement may create several instead ("twice that many", CR 614.1a): the extra ones are part of the
      # replaced event (`replaced`), so the replacement effects don't apply to them again (CR 614.5).
      def create_token!(definition, controller, tapped: false, memory: nil, enters: nil, replaced: false)
        definition = replace_token_creation!(definition, controller, tapped:, memory:, enters:) unless replaced
        obj = create_object(definition.id, controller, :battlefield)
        obj.memory.merge!(memory) if memory
        entering = enters # an "as this enters" choice made before it's created (CR 614.12a)
        tapped ||= entering&.dig("tapped") == true
        enters = propose("zone_change", { "object" => obj.id, "to" => :battlefield, "controller" => controller,
                                          "reason" => "create_token",
                                          "enters" => { "tapped" => tapped, "counters" => {} } }).data["enters"]
        merge_enters!(enters, entering.except("tapped")) if entering
        obj.memory.merge!(enters["memory"]) if enters["memory"]
        obj.controlled_since = state.turn
        obj.memory["entered"] = state.turn
        obj.tapped = enters["tapped"]
        obj.counters.merge!(enters["counters"])
        enter_as_copy!(obj, enters["copy"]) if enters["copy"] # CR 707.5 (Engine::Copies)
        state.battlefield.unshift(obj.id)
        enter_attacking!(obj) if enters["attacking"] # CR 508.4
        record_result!(obj.id)
        emit Events::ZoneChanged.new(card: definition.id, old_id: nil, new_id: obj.id, owner: name(controller),
                                     from: "none", to: "battlefield", reason: "create_token")
        prepare!(obj) if enters["prepared"] # CR 723.3a (Engine::Faces)
        obj
      end

      # The create_token replacements (CR 614.1a): the token definition to create, after creating the extra
      # ones a "twice that many" replacement adds.
      def replace_token_creation!(definition, controller, memory:, **)
        data = propose("create_token", { "player" => controller, "token" => definition.id, "count" => 1 }).data
        definition = catalog.fetch(data["token"])
        (data["count"] - 1).times do
          create_token!(definition, controller, memory: memory && Snapshot.deep_copy(memory), replaced: true, **)
        end
        definition
      end

      # CR 121.2: one card at a time. A replacement may turn one draw into several (CR 614.11); those
      # draws are the modified event, so the replacement that made them doesn't apply again (CR 614.5).
      def draw!(index, applied: [])
        proposal = propose("draw", { "player" => index, "count" => 1 }, applied)
        return unless proposal.data["player"]
        return proposal.data["count"].times { draw!(index, applied: proposal.applied) } if proposal.data["count"] != 1

        pl = player(index)
        if pl.library.empty?
          pl.drew_from_empty = true # CR 704.5b, checked as a state-based action
        else
          move!(pl.library.first, :hand, reason: "draw")
        end
      end

      def shuffle_library!(index)
        state.rng.shuffle!(player(index).library)
        emit Events::LibraryShuffled.new(player: name(index))
      end

      def tap!(object)
        object.tapped = true
        emit Events::Tapped.new(object: object.id)
      end

      # CR 701.26b: only tapped permanents can be untapped. Replacement effects (a stun counter,
      # CR 122.1d) may stop it.
      def untap!(object)
        return unless object.tapped
        return if propose("untap", { "object" => object.id }).data["cancelled"]

        object.tapped = false
        emit Events::Untapped.new(object: object.id)
        end_while_source_effects!(object.id, %w[while_source_tapped]) # CR 611.2b: "for as long as it remains tapped" ends
      end

      # CR 502.3: the active player's permanents untap, except those effects keep from untapping and those
      # they chose to keep tapped (`keep`, see Engine::TurnStructure).
      # An exerted permanent skips this one untap step (CR 701.43a).
      def untap_all!(index, keep: [])
        state.battlefield.each do |id|
          obj = object(id)
          next unless obj.controller == index

          exerted = obj.memory.delete("exerted")
          untap!(obj) unless keep.include?(id) || exerted || chars(obj).keyword?(:doesnt_untap)
        end
      end

      # CR 701.43a-b: exerting it (again) means it won't untap during its controller's next untap step.
      def exert!(obj) = obj.memory["exerted"] = true

      # CR 302.6: a creature's {T} abilities need it under continuous control since
      # the start of its controller's most recent turn.
      def summoning_sick_for_tap?(object)
        current = chars(object)
        return false if !current.creature? || current.keyword?(:haste)

        most_recent_turn = state.active == object.controller ? state.turn : state.turn - 1
        object.controlled_since.nil? || object.controlled_since >= most_recent_turn
      end
    end

    include Zones
  end
end
