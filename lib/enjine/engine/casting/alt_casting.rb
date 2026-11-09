# frozen_string_literal: true

module Enjine
  class Engine
    # Alternative costs given by keyword abilities (CR 118.9, Abilities::AlternativeCost): flashback, harmonize,
    # mayhem, warp, evoke, web-slinging and sneak, plus convoke (CR 702.51), which changes how the total cost
    # is paid. Each keyword is a cast *method* of Engine::Permissions:
    #   {"via" => "alt:<ref>", "play" => "cast" | "play", "keyword" => "flashback", "instant" => true (sneak),
    #    "alt" => {"cost" => "{2}{R}", "ref" => ref, "exile" => true, "returns" => "tapped" | "unblocked",
    #              "harmonize" => true}}
    # and a warped card in exile has the method {"via" => "warped", "play" => "cast"} (CR 702.185a).
    #
    # How a spell was cast is remembered on the spell (memory "cast_from": the zone, "cast_with": the keyword)
    # and on the permanent it becomes (CR 400.7d), and each player's turn log keeps the keywords of the
    # spells they cast this turn ("cast_with"), for "if a spell was warped this turn" (CR 702.185c).
    module AltCasting
      HARMONIZE_TEXT = "Tap up to one untapped creature you control (harmonize)"
      RETURN_TEXT = { "tapped" => "Return a tapped creature you control to its owner's hand",
                      "unblocked" => "Return an unblocked attacking creature you control to its owner's hand" }.freeze

      # ---- methods ------------------------------------------------------------------------------

      # The cards in a hand with an alternative cost (only those can be cast from it with a method).
      def alt_cost_hand(player) = player.hand.select { |id| chars(id).abilities.any? { it.ability.kind == :alternative_cost } }

      # The alternative-cost methods of `obj` (a card `index` owns) that function now. A face-down card its owner
      # may look at is seen face up (a foretold card, CR 702.143a, 406.3a).
      def alt_methods(index, obj)
        return [] unless obj.owner == index && obj.kind == "card" && may_look?(obj, index)

        own = face_up(obj.id) { chars(obj).abilities }.filter_map do |inst|
          ability = inst.ability
          ability.method_for(inst.ref) if ability.kind == :alternative_cost && ability.functions?(self, obj, index)
        end
        own + warped_methods(index, obj)
      end

      # CR 702.185a: "Its owner may cast this card after the current turn has ended for as long as it remains
      # exiled." The exiled card remembers the turn it was warped in.
      def warped_methods(_index, obj)
        turn = obj.zone == :exile && obj.memory["warped"]
        turn && state.turn > turn ? [{ "via" => "warped", "play" => "cast" }] : []
      end

      # CR 702.187b: mayhem needs the card to have been discarded this turn (TurnHistory stamps it).
      def discarded_this_turn?(obj) = !turned_memory(obj, "discarded").nil?

      # The non-mana parts of the alternative cost being paid (a list of costs, CR 601.2h).
      def alt_cost_parts(obj, method)
        ref = method&.dig("alt", "ref") or return []
        chars(obj).ability(ref).choosing_costs
      end

      def alt_parts_payable?(obj, method) = alt_cost_parts(obj, method).all? { it.payable?(self, obj) }

      # ---- returning a creature (beam me up, web-slinging, sneak) -------------------------------------

      # Whether an alternative cost returns a creature to its owner's hand (Engine::Permissions#beam_choices).
      def returns_creature?(alt) = !alt.nil? && (alt.key?("beam") || alt.key?("returns"))

      # The creatures `index` could return for the alternative cost `alt`: any (beam me up, CR 702.196a), a
      # tapped one (web-slinging, CR 702.188a) or an unblocked attacking one (sneak, CR 702.190a).
      def return_candidates(index, alt)
        case alt["returns"]
        when "tapped" then state.battlefield.select { (o = object(it)).controller == index && o.tapped && chars(o).creature? }
        when "unblocked"
          attackers.filter_map { |id, a| id if !a["blocked"] && object(id).controller == index && chars(id).creature? }
        else beam_candidates(index, alt["not"])
        end
      end

      # ---- harmonize (CR 702.180a-b) --------------------------------------------------------------

      def harmonize_candidates(index)
        state.battlefield.select { (o = object(it)).controller == index && !o.tapped && chars(o).creature? }
      end

      # The largest reduction harmonize could give `index` now (for whether the card is castable).
      def best_harmonize_power(index, method)
        return 0 unless method.dig("alt", "harmonize")

        harmonize_candidates(index).map { [chars(it).power.to_i, 0].max }.max || 0
      end

      # CR 702.180a: the total cost is reduced by generic mana equal to the tapped creature's power.
      def harmonize_reduced(cost, power)
        return cost if cost.nil? || !power.positive?

        cost.with(generic: [cost.generic - power, 0].max)
      end

      # Costs#frame_total_cost: the cast in progress's reduction.
      def frame_harmonize_power(ctx) = ctx.dig("harmonize", "power").to_i

      # CR 702.180b: the creature is chosen as the harmonize cost is chosen, before the total cost is locked.
      def harmonize_pending?(ctx) = ctx["kind"] == "spell" && ctx.dig("method", "alt", "harmonize") && !ctx.key?("harmonize")

      def ask_harmonize!(ctx)
        ask!("kind" => "choose_cost", "player" => ctx["player"], "cost" => HARMONIZE_TEXT)
        :wait
      end

      # Options: each untapped creature, or none (`{type: "cost"}`).
      def harmonize_options(ctx) = harmonize_candidates(ctx["player"]).map { { object: it } } + [{}]

      # The creature is tapped now (cancelling untaps it); its power is the reduction.
      def choose_harmonize!(ctx, id)
        ctx["harmonize"] = { "creature" => id, "power" => id ? [chars(id).power.to_i, 0].max : 0 }
        if id
          tap!(object(id))
          ctx["tapped"] << id
        end
        ask!(nil)
      end

      # The zone a spell is (being) cast from (CR 601.2a): remembered once cast, the cast frame's origin
      # while it's being cast, or the zone a card is in before it's cast (when its cost is estimated).
      def cast_origin(spell)
        return spell.zone.to_s unless spell.zone == :stack

        spell.memory["cast_from"] || state.frames.rfind { it["object"] == spell.id }&.dig("origin", "zone") || "hand"
      end

      # ---- as the spell becomes cast --------------------------------------------------------------

      # Where the spell was cast from and with which keyword (CR 601.2a, 400.7d); a warp spell's delayed
      # trigger (CR 702.185a); the creatures that convoked it (CR 702.51c).
      def record_cast_how!(obj, ctx)
        obj.memory["cast_from"] = ctx.dig("origin", "zone") || "hand"
        obj.memory["convoked"] = ctx["convoked"].dup if ctx["convoked"]
        return unless ctx.dig("method", "alt") # mayhem without a cost: no keyword cost was paid

        keyword = ctx.dig("method", "keyword") or return
        obj.memory["cast_with"] = keyword
        (turn_log(ctx["player"])["cast_with"] ||= []) << keyword
        warp_delayed!(obj, ctx) if keyword == "warp"
      end

      def warp_delayed!(obj, ctx)
        ability = chars(obj).ability(ctx.dig("method", "alt", "ref"))
        create_delayed_trigger!("controller" => ctx["player"], "source" => obj.id, "card" => obj.card,
                                "ability" => ability.delayed.ref, "watched" => [obj.id])
      end

      # The creature returned for beam me up, web-slinging or sneak goes to its owner's hand as the spell
      # becomes cast (CR 601.2h); a sneak spell remembers what it was attacking (CR 702.190b).
      def returned_creature!(obj, ctx)
        creature = ctx["beam_creature"]
        alt = ctx.dig("method", "alt")
        obj.memory["sneak_attack"] = attackers.dig(creature, "target") if alt["returns"] == "unblocked"
        move!(creature, :hand, reason: alt.key?("beam") ? "beam_me_up" : ctx.dig("method", "keyword"))
      end

      # The permanent a spell becomes remembers how it was cast; a warp spell's permanent is watched by the
      # delayed trigger; a sneak spell's enters tapped and attacking (CR 702.190b, 506.3a). Cards its costs
      # exiled stay linked to it ("behold a Goblin and exile it", CR 607.2a).
      def alt_enters!(spell, enters)
        how = spell.memory.slice("cast_from", "cast_with", Mechanics::Linked::EXILED, "haste_while_controlled_by")
        how["warp_spell"] = spell.id if spell.memory["cast_with"] == "warp"
        (enters["memory"] ||= {}).merge!(how) unless how.empty?
        target = spell.memory["sneak_attack"] or return
        enters["tapped"] = true
        enters["attacking"] = target if target.start_with?("player:") || state.battlefield.include?(target)
      end

      # ---- convoke (CR 702.51) and improvise (CR 702.126) ------------------------------------------

      # Who helps pay: convoke taps creatures (for {1} or one mana of their color), improvise artifacts
      # (for {1} only). Neither is an additional or alternative cost (CR 702.51b, 702.126b).
      HELPERS = { "convoke" => :creature, "improvise" => :artifact }.freeze

      def convoke?(spell) = helper_keywords(spell).include?("convoke")
      def helper_keywords(spell) = spell.nil? ? [] : HELPERS.keys.select { chars(spell).keyword?(it.to_sym) }

      # Mana units (Engine::ManaSources) the permanents `index` could convoke or improvise with add for
      # `purpose`: one per untapped helper that isn't counted as a mana source, paying {1} or (convoke) one
      # of its colors; an improvise-only unit has no type, so it pays only generic mana.
      def convoke_units(index, purpose, excluded = [])
        spell = purpose&.[]("spell")
        spell = state.objects[spell] unless spell.is_a?(GameObject)
        kinds = helper_keywords(spell)
        return [] if kinds.empty?

        sources = all_mana_sources(index).map(&:first)
        kinds.flat_map { convoke_candidates(index, it) }.uniq.reject { excluded.include?(it) || sources.include?(it) }.map do |id|
          kinds.include?("convoke") && chars(id).creature? ? chars(id).colors : []
        end
      end

      def convoke_candidates(index, kind = "convoke")
        state.battlefield.select { (o = object(it)).controller == index && !o.tapped && chars(o).type?(HELPERS[kind]) }
      end

      # pay_cost options: `{type: "convoke" | "improvise", object: id}` for each helper that can pay part of what is left.
      def convoke_options
        frame = payment
        return [] unless frame["type"] == "cast" && frame["kind"] == "spell"

        helper_keywords(object(frame["object"])).flat_map do |kind|
          convoke_candidates(frame["player"], kind).filter_map do |id|
            { type: kind, object: id } if convoke_slot(frame, id, kind)
          end
        end
      end

      # The part of the remaining cost the permanent pays: for convoke a colored or hybrid symbol of one of its
      # colors, else generic (or half of a {2/B} paid as {2}, CR 107.4e, 601.2b); for improvise only generic (one
      # that keeps the rest payable once the payment is irreversible).
      def convoke_slot(frame, id, kind = "convoke")
        rem = frame["remaining"]
        colors = kind == "convoke" ? chars(id).colors : []
        slots = colors.flat_map { pay_slots(rem, it.to_s) }.select { %i[color hybrid].include?(it.first) }.uniq
        slots << [:generic] if rem["generic"].positive?
        slots += pay_slots(rem, "C").select { it.first == :two_generic }
        return slots.first unless frame["irreversible"]

        pl = player(frame["player"])
        slots.find do |slot|
          payable_with?(frame, remaining_cost(after_paying(rem, slot)), pl.mana_pool.dup, payment_reserved(frame) + [id],
                        restricted: pl.restricted_mana)
        end
      end

      # CR 702.51a, 702.126a: tapping the permanent pays that mana; cancelling untaps it.
      def convoke!(id, kind = "convoke")
        frame = payment
        frame["remaining"] = after_paying(frame["remaining"], convoke_slot(frame, id, kind))
        tap!(object(id))
        frame["tapped"] << id
        (frame["convoked"] ||= []) << id if kind == "convoke" # CR 702.51c
        ask!(nil)
      end

      # ---- history ------------------------------------------------------------------------------------

      # CR 702.187b: a card discarded this turn is stamped in the graveyard (TurnHistory#object_memory!).
      def discard_recorded!(event)
        return unless event.reason == "discard" && event.to == "graveyard" && state.objects.key?(event.new_id)

        object_memory!(event.new_id, "discarded")
      end

      # Whether any player cast a spell with `keyword`'s cost this turn (CR 702.185c: "a spell was warped").
      def cast_with_this_turn?(keyword) = state.players.each_index.any? { Array(turn_log(it)["cast_with"]).include?(keyword) }
    end

    include AltCasting
  end
end
