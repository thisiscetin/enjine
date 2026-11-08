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
    #    "once" => {"source" => id, "ref" => ref}} # "once during each of your turns"
    #
    # Permissions granted by resolved effects are `state.effects` entries of kind "permission"
    # (see #grant_play_permission!); the others come from abilities (Abilities::PlayFrom, BeamMeUp).
    module Permissions
      FREE = { "free" => true }.freeze
      ZERO = Mana::Cost.new(generic: 0, colored: {}.freeze)
      BEAM_COST_TEXT = "Return a creature you control to its owner's hand"

      # ---- legal actions --------------------------------------------------------------------

      # Cards outside the hand `index` might play: their graveyard, every exiled card and their library's
      # top card (deterministic order: graveyard, exile, library).
      def permission_candidates(index)
        pl = player(index)
        ids = pl.graveyard + state.exile
        pl.library.empty? ? ids : ids + [pl.library.first]
      end

      # Priority options: `{type: "cast", object: id, via: method}` for every castable card and method.
      def permission_cast_options(index)
        sources = permission_sources(index)
        permission_candidates(index).flat_map do |id|
          play_methods(index, id, sources).filter_map do |method|
            { type: "cast", object: id, via: method["via"] } if castable_via?(index, id, method)
          end
        end
      end

      # Priority options: lands `index` may play from outside their hand (CR 305.1, 305.2).
      def permission_land_options(index)
        sources = permission_sources(index)
        permission_candidates(index).flat_map do |id|
          next [] unless chars(id).land?

          play_methods(index, id, sources).filter_map do |method|
            { type: "play_land", object: id, via: method["via"] } if method["play"] == "play"
          end
        end
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

      # Every method `index` has to play the card `id` now (before timing and cost checks).
      def play_methods(index, id, sources = permission_sources(index))
        obj = object(id)
        granted_methods(index, obj) + own_methods(index, obj) + static_methods(index, obj, sources) +
          beam_methods(index, obj, sources)
      end

      # The method named `via`, or an error (the option was offered from this list).
      def play_method(index, id, via)
        return { "via" => "free", "play" => "cast", "alt" => FREE } if via == "free"

        play_methods(index, id).find { it["via"] == via } or raise ArgumentError, "#{id} can't be played via #{via}"
      end

      # CR 601.3: whether `index` may begin to cast the card this way now. Timing still applies outside
      # resolution (CR 304.1, 307.1); a card without a mana cost needs an alternative cost (CR 118.6a).
      def castable_via?(index, id, method)
        obj = object(id)
        c = chars(obj)
        return false if c.land? || (method["alt"].nil? && c.mana_cost.nil?) # CR 305.9
        return false unless c.type?(:instant) || c.keyword?(:flash) || sorcery_timing?(index)
        return false if method.dig("alt", "beam") && beam_candidates(index, method["alt"]["not"]).empty?
        return false unless additional_costs_payable?(obj) # CR 601.2f

        cost = Mana.sum_costs([method_cost(obj, method), *spell_extra_mana(obj, false)])
        ability_targetable?(spell_ability_of(obj), index, id) && affordable?(index, total_cost(index, cost, spell: obj), nil)
      end

      # CR 608.2g: whether a card could be cast now during resolution without paying its mana cost
      # (timing doesn't apply; lands can't be cast, CR 305.9; it needs legal targets, CR 601.2c).
      def free_castable?(index, id)
        obj = object(id)
        obj.kind == "card" && !chars(obj).land? && additional_costs_payable?(obj) &&
          ability_targetable?(spell_ability_of(obj), index, id)
      end

      # The mana cost paid with a method: the card's own, nothing (CR 118.9) or the beam me up cost.
      def method_cost(obj, method)
        alt = method && method["alt"]
        return chars(obj).mana_cost unless alt
        return ZERO if alt["free"]

        Mana::Cost.parse(alt["beam"])
      end

      # Costs#base_cost for a spell cast with an alternative cost (CR 118.9c: its mana cost is unchanged).
      def alternative_base_cost(ctx) = method_cost(object(ctx["object"]), ctx["method"])

      # ---- where methods come from ------------------------------------------------------------

      # Permissions from resolved effects (impulse draw, CR 611.2): the card is still the exiled object.
      def granted_methods(index, obj)
        state.effects.filter_map do |e|
          next unless e["kind"] == "permission" && e["controller"] == index && e["affected"].include?(obj.id)

          { "via" => "effect:#{e["timestamp"]}", "play" => e["play"] } if obj.zone == :exile
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
      def grant_play_permission!(index, ids, duration:, play:)
        return if ids.empty?

        state.effects << { "kind" => "permission", "timestamp" => next_timestamp!, "controller" => index,
                           "affected" => ids, "duration" => duration, "turn" => state.turn, "play" => play }
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
      def beam_choices(ctx) = beam_candidates(ctx["player"], ctx.dig("method", "alt", "not"))

      # True while the beam me up creature still has to be chosen (or the chosen one is no longer there).
      def beam_choice_pending?(ctx)
        return false unless ctx.dig("method", "alt", "beam")
        return false if ctx["beam_creature"] && beam_choices(ctx).include?(ctx["beam_creature"])

        ctx.delete("beam_creature")
        true
      end

      def ask_beam_choice!(ctx)
        ask!("kind" => "choose_cost", "player" => ctx["player"], "cost" => BEAM_COST_TEXT)
        :wait
      end

      # CR 601.2h: the creature is chosen now and returned when the spell becomes cast, so cancelling
      # never has to bring a permanent back.
      def choose_beam_creature!(id)
        casting["beam_creature"] = id
        ask!(nil)
      end

      # As the spell becomes cast (CR 601.2h-i): return the beam creature, remember the riders and use up
      # a "once each turn" permission.
      def finish_cast_method!(obj, ctx)
        method = ctx["method"] or return
        move!(ctx["beam_creature"], :hand, reason: "beam_me_up") if ctx["beam_creature"]
        obj.memory["beamed"] = true if method.dig("alt", "beam")
        obj.memory["enters_with"] = method["enters_with"] if method["enters_with"]
        use_play_method!(method)
      end

      # Replacement effects of how a spell was cast (CR 614.1a, 614.12): a beamed-up spell is exiled
      # whenever it would leave the stack (CR 702.196a); a permanent spell cast with an "enters with"
      # rider gets those counters as it enters.
      def cast_replacements!(proposal)
        data = proposal.data
        obj = state.objects[data["object"]]
        return unless obj && obj.zone == :stack

        data["to"] = :exile if obj.memory["beamed"] && data["to"] != :exile
        extra = obj.memory["enters_with"]
        return unless extra && data["to"] == :battlefield

        extra.each { |name, n| data["enters"]["counters"][name] = data["enters"]["counters"].fetch(name, 0) + n }
      end

      # A cancelled cast (Casting#cancel_casting!): the card goes back where it came from as the same object
      # (CR 733.1), hand, graveyard, exile or library, at its old position. So a permission naming it applies.
      def restore_to_origin!(obj, origin)
        zone = origin.fetch("zone", "hand").to_sym
        state.objects[origin["id"]] = GameObject.new(
          id: origin["id"], card: obj.card, owner: obj.owner, controller: obj.owner, zone: zone, tapped: false,
          controlled_since: nil, kind: "card", counters: {}, damage: 0, source: nil, ability: nil, targets: nil,
          loyalty_turn: nil, deathtouched: false, modes: nil, memory: {}, attached_to: nil
        )
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
