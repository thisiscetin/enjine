# frozen_string_literal: true

module Enjine
  class Engine
    # Playing cards from zones other than the hand (CR 601.3, 116.2a, 305.1): a card's own permission
    # to be cast from the graveyard or exile, impulse draw (exiled cards playable for a while),
    # beam me up (CR 702.196) and casting during resolution without paying the mana cost (CR 608.2g,
    # 118.9).
    #
    # A way to play a card is a *method*, plain data carried by the priority option (`via`) and by the
    # cast frame (`"method"`):
    #   {"via" => "effect:12" | "self:printed:1" | "static:<permanent>:<ref>" | "beam:<ref>" |
    #             "beam_granted:<permanent>:<ref>" | "free",
    #    "play" => "cast" | "play",              # "play" also allows a land to be played (CR 305.1)
    #    "alt" => nil | {"free" => true} | {"beam" => "{3}{W}", "not" => id},  # alternative cost (CR 118.9)
    #    "enters_with" => {counter => n},         # "if you cast it this way, it enters with ..."
    #    "once" => {"source" => id, "ref" => ref}, # "once during each of your turns"
    #    "cost_increase" => n}                     # riders of a permission effect (PlayPermission), e.g. 601.2f
    #
    # Permissions granted by resolved effects are `state.effects` entries of kind "permission"
    # (see #grant_play_permission!); the others come from abilities (Abilities::PlayFrom, BeamMeUp).
    #
    # Cards outside the game (CR 400.11) aren't objects: a player's are definition ids in
    # PlayerState#outside. Options name one as `"outside:<card id>"` (#outside_key); legality checks use a
    # detached GameObject in the pseudo-zone :outside that is never stored (#outside_object), and the
    # object is created only when the card is brought into the game (#bring_in_from_outside!).
    module Permissions
      FREE = { "free" => true }.freeze
      ZERO = Mana::Cost.new(generic: 0, colored: {}.freeze)
      BEAM_COST_TEXT = "Return a creature you control to its owner's hand"
      OUTSIDE = "outside:"
      # Permission effect fields copied into the play method (see Effects::PlayPermission); "alt" is an
      # alternative cost, {"cost" => "{2}"} (airbend, CR 701.65a, 118.9).
      RIDERS = %w[cost_increase any_mana_type alt exile_instead].freeze

      # ---- legal actions --------------------------------------------------------------------

      # Cards `index` might play by a permission or an alternative cost: their hand (alternative costs such
      # as warp, Engine::AltCasting), graveyard, every exiled card and their library's top card (deterministic
      # order: hand, graveyard, exile, library), then the cards they own outside the game (one key per
      # distinct card) while something lets them play those.
      def permission_candidates(index, sources = permission_sources(index))
        pl = player(index)
        ids = alt_cost_hand(pl) + pl.graveyard + state.exile
        ids += [pl.library.first] unless pl.library.empty?
        return ids unless sources.any? { |_, inst| inst.ability.kind == :play_from && inst.ability.outside? }

        ids + pl.outside.uniq.map { outside_key(it) }
      end

      # Priority options: `{type: "cast", object: id, via: method}` for every castable card and method.
      def permission_cast_options(index)
        sources = permission_sources(index)
        permission_candidates(index, sources).flat_map do |ref|
          obj = candidate_object(index, ref)
          play_methods(index, obj, sources).filter_map do |method|
            { type: "cast", object: ref, via: method["via"] } if castable_via?(index, obj, method)
          end
        end
      end

      # Priority options: lands `index` may play from outside their hand (CR 305.1, 305.2).
      def permission_land_options(index)
        sources = permission_sources(index)
        permission_candidates(index, sources).flat_map do |ref|
          obj = candidate_object(index, ref)
          next [] unless face_up(obj.id) { chars(obj).land? } # a face-down card is played face up (CR 406.3a)

          play_methods(index, obj, sources).filter_map do |method|
            { type: "play_land", object: ref, via: method["via"] } if method["play"] == "play"
          end
        end
      end

      # ---- cards outside the game (CR 400.11, 400.11b, 108.3) -------------------------------------

      def outside_key(card) = "#{OUTSIDE}#{card}"
      def outside_key?(ref) = ref.is_a?(String) && ref.start_with?(OUTSIDE)
      def outside_card(ref) = ref.delete_prefix(OUTSIDE)

      # A detached object standing for a card `index` owns outside the game, for legality checks only.
      def outside_object(index, card)
        GameObject.new(id: outside_key(card), card: card, owner: index, controller: index, zone: :outside, tapped: false,
                       controlled_since: nil, kind: "card", counters: {}, damage: 0, source: nil, ability: nil,
                       targets: nil, loyalty_turn: nil, deathtouched: false, modes: nil, memory: {}, attached_to: nil)
      end

      # The object an option names: a game object, or the detached stand-in of a card outside the game.
      def candidate_object(index, ref) = outside_key?(ref) ? outside_object(index, outside_card(ref)) : object(ref)

      # CR 400.11b, 108.3: one copy of `card` leaves `index`'s outside list and enters the game in `to` as a
      # new object they own, through the usual entering replacements (CR 614.12) when it's the battlefield.
      def bring_in_from_outside!(index, card, to, reason:, enters: nil)
        list = player(index).outside
        at = list.index(card) or raise ArgumentError, "#{name(index)} has no #{card} outside the game"
        list.delete_at(at)
        obj = create_object(card, index, to)
        data = { "object" => obj.id, "to" => to, "controller" => index, "reason" => reason }
        if to == :battlefield
          data["enters"] = { "tapped" => enters&.fetch("tapped", false) == true, "counters" => {} }
          data = propose("zone_change", data).data
          merge_enters!(data["enters"], enters.except("tapped")) if enters
        end
        arrive!(obj, obj, data)
        state.zone_list(to, index).unshift(obj.id)
        record_result!(obj.id)
        emit Events::ZoneChanged.new(card: card, old_id: nil, new_id: obj.id, owner: name(index), from: "outside",
                                     to: to.to_s, reason: reason)
        obj
      end

      # CR 601.2a: a spell cast from outside the game is brought into the game onto the stack.
      def begin_outside_cast!(index, ref, via)
        method = play_method(index, ref, via)
        card = outside_card(ref)
        origin = { "zone" => "outside", "card" => card, "index" => player(index).outside.index(card) }
        obj = bring_in_from_outside!(index, card, :stack, reason: "cast")
        start_casting!(index, obj.id, "spell", origin: origin, extra: { "method" => method })
      end

      # CR 305.1: a land played (from a zone or from outside the game) is put onto the battlefield.
      def put_played_land!(index, ref, enters: nil)
        return bring_in_from_outside!(index, outside_card(ref), :battlefield, reason: "play_land", enters: enters) if outside_key?(ref)

        move!(ref, :battlefield, controller: index, reason: "play_land", enters: enters)
      end

      # Permanents `index` controls whose static abilities let them play cards from other zones:
      # [[permanent, AbilityInstance], ...].
      def permission_sources(index)
        state.battlefield.flat_map do |id|
          obj = object(id)
          next [] unless obj.controller == index

          chars(obj).abilities.filter_map do |inst|
            [obj, inst] if inst.ability.kind == :grants_beam_me_up || (inst.ability.kind == :play_from && !inst.ability.self?)
          end
        end
      end

      # Every method `index` has to play the card `id` (an object, its id or an outside key) now (before
      # timing and cost checks).
      def play_methods(index, id, sources = permission_sources(index))
        obj = id.is_a?(GameObject) ? id : candidate_object(index, id)
        granted_methods(index, obj) + own_methods(index, obj) + static_methods(index, obj, sources) +
          beam_methods(index, obj, sources) + alt_methods(index, obj)
      end

      # The method named `via`, or an error (the option was offered from this list).
      def play_method(index, id, via)
        return { "via" => "free", "play" => "cast", "alt" => FREE } if via == "free"
        return { "via" => "resolving", "play" => "cast" } if via == "resolving" # CR 608.2g, 707.12: costs paid

        play_methods(index, id).find { it["via"] == via } or raise ArgumentError, "#{id} can't be played via #{via}"
      end

      # CR 601.3: whether `index` may begin to cast the card this way now. Timing still applies outside
      # resolution (CR 304.1, 307.1); a card without a mana cost needs an alternative cost (CR 118.6a).
      def castable_via?(index, id, method)
        obj = id.is_a?(GameObject) ? id : candidate_object(index, id)
        return face_up(obj.id) { castable_via?(index, obj, method) } if face_down?(obj) && @face_up != obj.id # CR 406.3a

        c = chars(obj)
        return false if c.land? || (method["alt"].nil? && c.mana_cost.nil?) # CR 305.9
        return false unless c.type?(:instant) || c.keyword?(:flash) || method["instant"] || sorcery_timing?(index)
        return false if cast_forbidden?(index, obj) # CR 101.2
        return false if returns_creature?(method["alt"]) && return_candidates(index, method["alt"]).empty?
        return false unless additional_costs_payable?(obj) && alt_parts_payable?(obj, method) # CR 601.2f

        # CR 609.4b; a stand-in for a card outside the game is passed itself (it isn't in state.objects).
        purpose = { "spell" => state.objects.key?(obj.id) ? obj.id : obj, "any_type" => method["any_mana_type"] }.compact
        ability_targetable?(spell_ability_of(obj), index, obj.id) &&
          cost_variant_affordable?(index, spell_cost_list(obj, false), obj, method_cost(obj, method), nil, purpose) do
            harmonize_reduced(total_cost(index, it, spell: obj), best_harmonize_power(index, method)) # CR 601.2b
          end
      end

      # CR 608.2g: whether a card could be cast now during resolution without paying its mana cost
      # (timing doesn't apply; lands can't be cast, CR 305.9; it needs legal targets, CR 601.2c).
      def free_castable?(index, id)
        obj = object(id)
        obj.kind == "card" && !chars(obj).land? && !cast_forbidden?(index, obj) && additional_costs_payable?(obj) &&
          ability_targetable?(spell_ability_of(obj), index, id)
      end

      # CR 608.2g, 707.12: whether a card could be cast now during resolution, paying its costs.
      # `any_mana_type`: mana of any type can be spent to cast it (CR 609.4b).
      def castable_while_resolving?(index, id, any_mana_type: nil)
        obj = object(id)
        own = chars(obj).mana_cost or return false # CR 118.6a: no mana cost, can't be cast paying it
        purpose = { "spell" => id, "any_type" => any_mana_type }.compact
        free_castable?(index, id) &&
          cost_variant_affordable?(index, spell_cost_list(obj, false), obj, own, nil, purpose) do
            total_cost(index, it, spell: obj)
          end
      end

      # The mana cost paid with a method: the card's own, nothing (CR 118.9) or the beam me up cost, plus a
      # permission's cost increase ("spells cast this way cost {2} more", CR 601.2f).
      def method_cost(obj, method)
        alt = method && method["alt"]
        cost = if alt.nil? then chars(obj).mana_cost
               elsif alt["free"] then ZERO
               else Mana::Cost.parse(alt["beam"] || alt["cost"]) # beam me up, or a keyword's (Engine::AltCasting)
               end
        increase = method && method["cost_increase"]
        increase && cost ? cost.with(generic: cost.generic + increase) : cost
      end

      # Costs#base_cost for a spell cast with an alternative cost (CR 118.9c: its mana cost is unchanged).
      def alternative_base_cost(ctx) = method_cost(object(ctx["object"]), ctx["method"])

      # ---- where methods come from ------------------------------------------------------------

      # Permissions from resolved effects (impulse draw, CR 611.2): the card is still the exiled object. A
      # face-down card only for a player who may look at it (CR 406.3b). `any_mana_type`: mana of any type
      # can be spent to cast it (CR 609.4b).
      def granted_methods(index, obj)
        state.effects.filter_map do |e|
          next unless e["kind"] == "permission" && e["controller"] == index && e["affected"].include?(obj.id)
          next unless obj.zone == :exile && may_look?(obj, index)

          { "via" => "effect:#{e["timestamp"]}", "play" => e["play"], **e.slice(*RIDERS) }
        end
      end

      # The card's own permission to be cast from its graveyard or exile (CR 113.6e-f): its owner's.
      def own_methods(index, obj)
        return [] unless obj.owner == index

        chars(obj).abilities.filter_map do |inst|
          ability = inst.ability
          next unless ability.kind == :play_from && ability.self? && ability.holds?(self, obj)

          { "via" => "self:#{inst.ref}", "play" => ability.play, "enters_with" => ability.enters_with }.compact
        end
      end

      # Static abilities of permanents `index` controls, for cards they own in the named zone.
      def static_methods(index, obj, sources)
        return [] unless obj.owner == index

        sources.filter_map do |perm, inst|
          ability = inst.ability
          next unless ability.kind == :play_from && ability.holds?(self, obj) && ability.cards.match?(self, obj)
          next if ability.once && (state.active != index || once_used?(perm, inst.ref))

          { "via" => "static:#{perm.id}:#{inst.ref}", "play" => ability.play, "enters_with" => ability.enters_with,
            "once" => ability.once ? { "source" => perm.id, "ref" => inst.ref } : nil }.compact
        end
      end

      # CR 702.196a: beam me up functions from the graveyard, for an instant or sorcery card. A permanent
      # may grant it during its controller's main phase with the card's mana cost as the cost.
      def beam_methods(index, obj, sources)
        c = chars(obj)
        return [] unless obj.zone == :graveyard && obj.owner == index && (c.type?(:instant) || c.type?(:sorcery))

        own = c.abilities.filter_map do |inst|
          next unless inst.ability.kind == :beam_me_up

          { "via" => "beam:#{inst.ref}", "play" => "cast", "alt" => { "beam" => inst.ability.cost.to_s } }
        end
        own + granted_beams(index, c, sources)
      end

      def granted_beams(index, chars, sources)
        return [] unless chars.mana_cost && state.active == index && Steps::MAIN_PHASE_STEPS.include?(state.step)

        sources.filter_map do |perm, inst|
          next unless inst.ability.kind == :grants_beam_me_up

          { "via" => "beam_granted:#{perm.id}:#{inst.ref}", "play" => "cast",
            "alt" => { "beam" => chars.mana_cost.to_s, "not" => perm.id } } # not the granting creature itself
        end
      end

      # A once-per-turn permission: the permanent remembers the turn it was last used.
      def once_used?(perm, ref) = perm.memory.fetch("play_from_turns", {})[ref] == state.turn

      def use_play_method!(method)
        once = method && method["once"] or return
        perm = state.objects[once["source"]] or return
        (perm.memory["play_from_turns"] ||= {})[once["ref"]] = state.turn
      end

      # ---- permissions granted by effects -------------------------------------------------------

      # Permission to play exiled cards for a duration (CR 611.2): a continuous effect for the exiled
      # objects (a card that leaves exile is a new object, CR 400.7, so the permission ends with it).
      # `riders` (RIDERS) change how a card is played with this permission, and only then.
      def grant_play_permission!(index, ids, duration:, play:, **riders)
        return if ids.empty?

        state.effects << { "kind" => "permission", "timestamp" => next_timestamp!, "controller" => index,
                           "affected" => ids, "duration" => duration, "turn" => state.turn, "play" => play,
                           **riders.transform_keys(&:to_s).slice(*RIDERS) }
        emit Events::EffectStarted.new(kind: "permission", affected: ids, details: { "duration" => duration, "play" => play })
      end

      # CR 514.2: at cleanup, an end_of_your_next_turn permission ends on its controller's next turn, and a
      # permission whose cards all left exile is gone. (end_of_turn ones end with the other
      # until-end-of-turn effects.)
      def expire_permissions!
        state.effects.reject! do |e|
          next false unless e["kind"] == "permission"

          (e["duration"] == "end_of_your_next_turn" && state.active == e["controller"] && state.turn > e["turn"]) ||
            e["affected"].none? { state.exile.include?(it) }
        end
      end

      # ---- beam me up: the creature returned as part of the cost (CR 702.196a-b) ---------------------

      # Creatures `index` could return: not one that can't be beamed up (CR 702.196b), nor `excluded` (a
      # permanent granting beam me up that says it can't be beamed up to cast a spell its way).
      def beam_candidates(index, excluded = nil)
        state.battlefield.select do |id|
          obj = object(id)
          c = chars(obj)
          obj.controller == index && id != excluded && c.creature? && !c.keyword?(:cant_be_beamed_up)
        end
      end

      # The choices for the cast in progress.
      def beam_choices(ctx) = return_candidates(ctx["player"], ctx.dig("method", "alt"))

      # True while the returned creature still has to be chosen (or the chosen one is no longer there).
      def beam_choice_pending?(ctx)
        return false unless returns_creature?(ctx.dig("method", "alt"))
        return false if ctx["beam_creature"] && beam_choices(ctx).include?(ctx["beam_creature"])

        ctx.delete("beam_creature")
        true
      end

      def ask_beam_choice!(ctx)
        text = AltCasting::RETURN_TEXT.fetch(ctx.dig("method", "alt", "returns"), BEAM_COST_TEXT)
        ask!("kind" => "choose_cost", "player" => ctx["player"], "cost" => text)
        :wait
      end

      # CR 601.2h: the creature is chosen now and returned when the spell becomes cast, so cancelling
      # never has to bring a permanent back.
      def choose_beam_creature!(id)
        casting["beam_creature"] = id
        ask!(nil)
      end

      # As the spell becomes cast (CR 601.2h-i): remember where it was cast from and how (Engine::AltCasting),
      # return the creature an alternative cost returns, remember the riders and use up a "once each turn"
      # permission.
      def finish_cast_method!(obj, ctx)
        record_cast_how!(obj, ctx)
        method = ctx["method"] or return
        returned_creature!(obj, ctx) if ctx["beam_creature"]
        obj.memory["leaves_to_exile"] = true if method.dig("alt", "beam") || method.dig("alt", "exile")
        # "If that spell would be put into a graveyard, exile it instead" (CR 614.1a)
        obj.memory["graveyard_to_exile"] = true if method["exile_instead"] &&
                                                   Mechanics::ExileInstead.applies?(self, method["exile_instead"], obj)
        obj.memory["enters_with"] = method["enters_with"] if method["enters_with"]
        use_play_method!(method)
      end

      # Replacement effects of how a spell was cast (CR 614.1a, 614.12): a beamed-up or flashed-back spell
      # is exiled whenever it would leave the stack (CR 702.196a, 702.34a), one cast with an `exile_instead`
      # rider whenever it would be put into a graveyard; a permanent spell cast with an
      # "enters with" rider gets those counters as it enters; a permanent remembers how its spell was cast
      # (CR 400.7d, Engine::AltCasting#alt_enters!).
      def cast_replacements!(proposal)
        data = proposal.data
        obj = state.objects[data["object"]]
        return unless obj && obj.zone == :stack

        data["to"] = :exile if obj.memory["leaves_to_exile"] && data["to"] != :exile
        data["to"] = :exile if obj.memory["graveyard_to_exile"] && data["to"] == :graveyard
        return unless data["to"] == :battlefield

        alt_enters!(obj, data["enters"])
        extra = obj.memory["enters_with"] or return
        extra.each { |name, n| data["enters"]["counters"][name] = data["enters"]["counters"].fetch(name, 0) + n }
      end

      # A cancelled cast (Casting#cancel_casting!): the card goes back where it came from as the same object
      # (CR 734.1), hand, graveyard, exile or library, at its old position. So a permission naming it applies.
      def restore_to_origin!(obj, origin)
        return player(obj.owner).outside.insert(origin["index"] || 0, obj.card) if origin["zone"] == "outside"

        zone = origin.fetch("zone", "hand").to_sym
        state.objects[origin["id"]] = GameObject.new(
          id: origin["id"], card: card_after_move(obj, zone), owner: obj.owner, controller: obj.owner, zone: zone, tapped: false,
          controlled_since: nil, kind: "card", counters: {}, damage: 0, source: nil, ability: nil, targets: nil,
          loyalty_turn: nil, deathtouched: false, modes: nil, memory: Snapshot.deep_copy(origin.fetch("memory", {})),
          attached_to: nil # a face-down card goes back face down (CR 406.3)
        )
        carry_copy_status!(state.objects[origin["id"]], obj, zone) # a card copy stays one (Engine::Copies)
        list = state.zone_list(zone, obj.owner)
        list.insert([origin["index"], list.size].min, origin["id"])
      end

      # ---- looking at the top card (CR 401.5) ------------------------------------------------

      # A permanent letting its controller look at the top card of their library at any time.
      def may_look_at_top?(index)
        state.battlefield.any? do |id|
          obj = object(id)
          obj.controller == index && chars(obj).abilities.any? { it.ability.kind == :look_at_top }
        end
      end
    end

    include Permissions
  end
end
