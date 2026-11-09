# frozen_string_literal: true

module Enjine
  class Engine
    # Copying objects (CR 707).
    #
    # A copy takes the copiable values of the object it copies (CR 707.2): the values printed on its card,
    # as modified by other copy effects and their exceptions (CR 707.9b). Every copiable value comes from a
    # card definition plus a few exceptions, so a copy is kept as plain data on the GameObject:
    #
    #   obj.card                      the card whose printed values it has: the copied card while a copy
    #                                 effect applies (so its abilities, triggers and stack objects all
    #                                 resolve against that card's data)
    #   memory["own_card"]            the card the object really is, while a copy effect changed obj.card
    #   memory["copy_effects"]        copy effects on a permanent, in timestamp order (CR 613.7): each
    #                                 {"card", "except", "duration" ("permanent" | "end_of_turn"), "timestamp"}
    #   memory["copy_except"]         the exceptions of an object created as a copy (a token copy, CR 707.9)
    #   memory["token"]               true for a token that is a copy of a card (CR 111.1, 608.3f)
    #   memory["copy"]                "spell" for a copy of a spell (CR 707.10), "card" for a copy of a card
    #                                 (CR 707.12); they cease to exist outside the stack (and battlefield)
    #
    # Exceptions (CR 707.9a-b) are {"legendary": false, "keywords": [...], "types": [...], "subtypes": [...],
    # "supertypes": [...], "name": ..., "power": n, "toughness": n, "colors": [...]}; they are part of the
    # copy's copiable values, so copying a copy keeps them (CR 707.2).
    module Copies
      # ---- reading -------------------------------------------------------------------------------

      def own_card(obj) = obj.memory["own_card"] || obj.card

      # A token (CR 111.1): created as one, or a copy of a permanent spell that resolved (CR 608.3f).
      def token?(obj) = obj.memory["token"] == true || catalog.fetch(own_card(obj)).token?

      # The exceptions of the copy effect that applies (nil if none).
      def copy_exceptions(obj)
        effects = obj.memory["copy_effects"]
        effects && !effects.empty? ? effects.last["except"] : obj.memory["copy_except"]
      end

      # What a copy of `obj` gets: [card id, exceptions] (CR 707.2, 707.3).
      def copiable_values(obj) = [obj.card, copy_exceptions(obj) || {}]

      # 707.9b: exceptions of a later copy effect apply on top of those it copied.
      def self.merge_except(old, new)
        old ||= {}
        merged = old.merge(new.except("keywords", "types", "subtypes", "supertypes"))
        %w[keywords types subtypes supertypes].each do |key|
          list = Array(old[key]) | Array(new[key])
          merged[key] = list unless list.empty?
        end
        merged
      end

      # The characteristics with a copy effect's exceptions applied (CR 707.9a-b).
      def self.apply_exceptions(chars, except)
        attrs = {}
        attrs[:name] = except["name"] if except["name"]
        attrs[:supertypes] = chars.supertypes | sym(except["supertypes"])
        attrs[:supertypes] -= [:legendary] if except["legendary"] == false
        attrs[:types] = chars.types | sym(except["types"])
        attrs[:subtypes] = chars.subtypes | sym(except["subtypes"])
        attrs[:keywords] = chars.keywords | sym(except["keywords"])
        attrs[:colors] = sym(except["colors"]) if except["colors"]
        attrs[:power] = except["power"] if except.key?("power")
        attrs[:toughness] = except["toughness"] if except.key?("toughness")
        chars.with(**attrs.transform_values { it.is_a?(Array) ? it.freeze : it })
      end

      def self.sym(list) = Array(list).map(&:to_sym)

      # ---- making copies ---------------------------------------------------------------------------

      # CR 707.8, 111.1: a token that's a copy of [card, except], created under `controller`'s control.
      def create_token_copy!(values, controller, tapped: false)
        card, except = values
        memory = { "token" => true }
        memory["copy_except"] = except unless except.empty?
        create_token!(catalog.fetch(card), controller, tapped: tapped, memory: memory)
      end

      # CR 707.4, 613.2a: `obj` becomes a copy of [card, except]; no enter or leave triggers. A
      # "permanent" copy effect lasts as long as the object stays on the battlefield.
      def become_copy!(obj, values, duration: "permanent")
        card, except = values
        obj.memory["own_card"] ||= obj.card
        (obj.memory["copy_effects"] ||= []) << { "card" => card, "except" => except, "duration" => duration,
                                                 "timestamp" => next_timestamp! }
        obj.card = card
        emit Events::EffectStarted.new(kind: "copy", affected: [obj.id], details: { "card" => card })
      end

      # CR 707.5: a permanent entering as a copy ({"card", "except"}) is one as it enters.
      def enter_as_copy!(fresh, copy)
        fresh.memory["own_card"] = fresh.card
        fresh.memory["copy_effects"] = [copy.merge("duration" => "permanent", "timestamp" => next_timestamp!)]
        fresh.card = copy["card"]
      end

      # CR 707.12: a copy of a card, created in the zone the card is in (owned by `controller`).
      def create_card_copy!(values, controller, zone)
        card, except = values
        obj = create_object(card, controller, zone)
        obj.memory["copy"] = "card"
        obj.memory["copy_except"] = except unless except.empty?
        state.zone_list(zone, controller).unshift(obj.id)
        record_result!(obj.id)
        emit Events::ZoneChanged.new(card: card, old_id: nil, new_id: obj.id, owner: name(controller),
                                     from: "none", to: zone.to_s, reason: "copy")
        obj
      end

      # CR 707.10: a copy of a spell on the stack, with the same modes, X, kicker and other choices, put on
      # top of the stack by `controller` (who owns and controls it). It isn't cast.
      def copy_spell!(spell, controller, targets)
        card, except = copiable_values(spell)
        copy = create_object(card, controller, :stack)
        copy.memory = Marshal.load(Marshal.dump(spell.memory.slice("kicked", "kicked_with", "division"))).merge("copy" => "spell")
        copy.memory["copy_except"] = except unless except.empty?
        copy.targets = targets
        copy.modes = spell.modes&.dup
        copy.x = spell.x
        copy.mana_spent = nil # CR 707.10: mana isn't copied; no mana was spent to cast a copy
        copy.paid = spell.paid&.map(&:dup)
        state.stack.unshift(copy.id)
        record_result!(copy.id)
        emit Events::SpellCopied.new(player: name(controller), object: copy.id, card: card, original: spell.id,
                                     targets: targets)
        copy
      end

      # ---- zone changes and state-based actions ------------------------------------------------------

      # CR 400.7: the new object is the card itself again; a token or copy stays one. A copy of a permanent
      # spell becomes a token as it enters (CR 608.3f, 707.10f).
      def carry_copy_status!(fresh, old, to)
        fresh.memory["token"] = true if old.memory["token"]
        fresh.memory["copy_except"] = old.memory["copy_except"] if old.memory["copy_except"]
        kind = old.memory["copy"] or return
        return fresh.memory["token"] = true if kind == "spell" && to == :battlefield

        fresh.memory["copy"] = kind
      end

      # CR 704.5d, 111.7, 707.10a: tokens outside the battlefield, spell copies outside the stack and card
      # copies outside the stack and battlefield cease to exist (state-based actions).
      # Zones a token or card copy can be in (a phased-out permanent is still on the battlefield, CR 702.26d).
      STAYING = %i[battlefield stack phased_out].freeze

      def ceases_to_exist?(obj)
        return false if obj.ability?

        case obj.memory["copy"]
        when "spell" then obj.zone != :stack
        when "card" then !STAYING.include?(obj.zone) && !prepared_copy?(obj) # CR 723.3c (Engine::Faces)
        else !STAYING.include?(obj.zone) && token?(obj)
        end
      end

      # CR 514.2: "until end of turn" copy effects end; the permanent has the copiable values of the
      # newest copy effect left, or its own.
      def end_copy_effects!
        state.battlefield.each do |id|
          obj = object(id)
          effects = obj.memory["copy_effects"] or next
          next unless effects.any? { it["duration"] == "end_of_turn" }

          effects.reject! { it["duration"] == "end_of_turn" }
          obj.card = effects.last&.fetch("card") || obj.memory["own_card"]
          obj.memory.delete("copy_effects") if effects.empty?
          obj.memory.delete("own_card") if effects.empty?
          emit Events::EffectsEnded.new(count: 1)
        end
      end

      # ---- abilities granted to a card (CR 113.6b, 611.3) ----------------------------------------

      # Abilities an object gained from a resolved effect (state.effects "card_ability", lasting while it
      # stays in its zone or until end of turn), e.g. an exiled card: "granted:<granting card>:<ref>".
      def card_granted_abilities(obj)
        state.effects.filter_map do |effect|
          next unless effect["kind"] == "card_ability" && effect["affected"].include?(obj.id)

          ability = catalog.fetch(effect["card"]).ability(effect["ability"]) or next
          AbilityInstance.new(ref: "granted:#{effect["card"]}:#{effect["ability"]}", ability: ability)
        end
      end

      # Starts a "card_ability" effect; ones whose cards no longer exist are dropped.
      def grant_card_ability!(ctx, affected, card, ref, duration)
        state.effects.reject! { it["kind"] == "card_ability" && it["affected"].none? { state.objects.key?(it) } }
        duration = "while_in_zone" if duration == "permanent" # a new object is a different one (CR 400.7)
        state.effects << { "kind" => "card_ability", "timestamp" => next_timestamp!, "controller" => ctx.controller,
                           "affected" => affected, "duration" => duration, "card" => card, "ability" => ref }
        emit Events::EffectStarted.new(kind: "card_ability", affected: affected, details: { "card" => card })
      end
    end
    include Copies
  end
end
