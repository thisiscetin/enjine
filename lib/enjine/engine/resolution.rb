# frozen_string_literal: true

module Enjine
  class Engine
    # Resolving the top object of the stack (CR 608), as a resumable "resolve" frame:
    # the frame remembers which effect is next ("pc") and each effect's scratch data
    # ("locals"), so an effect may stop to ask a player and continue after the answer.
    module Resolution
      def begin_resolution!
        state.frames << { "type" => "resolve", "object" => state.stack.first, "pc" => nil, "ctx" => nil,
                          "locals" => {} }
      end

      # Records a player's answer for the effect that is asking (see Effects::ChoiceEffect). An effect
      # running a nested effect (a "may") keeps that effect's locals under "child": the innermost asks.
      def effect_answer!(option)
        (answering_locals["answers"] ||= []) << option.transform_keys(&:to_s)
        ask!(nil)
      end

      # The locals of the effect that is asking: the innermost one of the resolving effect list.
      def answering_locals
        frame = state.frames.rfind { it["type"] == "resolve" }
        locals = frame["locals"][frame["pc"].to_s]
        locals = locals["child"] while locals["child"]
        locals
      end

      def resolving_ability(obj)
        obj.ability? ? stack_ability(obj) : definition(obj).spell_ability
      end

      # CR 608.2n, 400.7: a spell that leaves the stack as part of its own resolution ("exile this spell") becomes a
      # new object, but its resolution goes on: its resolve frame keeps the spell as it last existed on the stack
      # ("left_stack"), which stands in for it (Engine#object) for the rest of its effects (a choice, a payment, a
      # reflexive trigger) and as it finishes resolving.
      def note_left_stack!(old)
        frame = state.frames.rfind { it["type"] == "resolve" && it["object"] == old.id } or return
        frame["left_stack"] = old.to_h
      end

      def resolving_stand_in(id)
        frame = state.frames.rfind { it["type"] == "resolve" && it["object"] == id }
        frame&.key?("left_stack") ? Snapshot.build_object(frame["left_stack"]) : nil
      end

      def step_resolution!(frame)
        obj = object(frame["object"])
        ability = resolving_ability(obj)
        start_resolution!(frame, obj, ability) if frame["pc"].nil?
        return finish_fizzle!(frame, obj) if frame["fizzled"]

        plan = ability ? ability.effect_plan(obj.modes || []) : []
        while frame["pc"] < plan.size
          effect, offset, count, index = plan[frame["pc"]]
          ctx = effect_context(frame["ctx"], offset, count, index ? frame["pc"] - index : 0)
          locals = (frame["locals"][frame["pc"].to_s] ||= {})
          return :wait if recording_results(frame) { simultaneously { effect.run(self, ctx, locals) } } == :wait
          return :done if frame["turn_ended"] # CR 725.1b: exiled mid-resolution (Engine::TurnStructure#end_the_turn!)

          frame["pc"] += 1
        end
        if !obj.ability? && definition(obj).permanent? && entering_choice_pending?(obj.id, frame["enter"])
          return ask_enter_choice!(obj.id, obj.controller, frame["enter"]) # CR 614.12: decided before it enters
        end

        gift_given!(obj, ability)
        emit Events::Resolved.new(object: obj.id, card: obj.card, kind: obj.kind)
        finish_resolution!(obj, frame)
        after_resolution!
      end

      # CR 702.174c: a player gives a gift as their instant or sorcery spell whose gift was promised resolves, or as
      # the gift triggered ability of their permanent resolves (an enters trigger checking "if the gift was promised").
      def gift_given!(obj, ability)
        given = if obj.ability? then ability.respond_to?(:condition) && Mechanics::Condition::CastHow.gift?(ability.condition)
                else obj.memory["kicked_with"] == "gift" && (chars(obj).type?(:instant) || chars(obj).type?(:sorcery))
                end
        emit Events::KeywordAction.new(player: name(obj.controller), action: "give_gift", amount: nil) if given
      end

      # CR 608.2b: targets are checked once, as resolution begins.
      def start_resolution!(frame, obj, ability)
        specs = ability&.targets_for(obj.modes || [], kicked: obj.memory.key?("kicked_with")) || []
        targets = legal_targets(obj, specs)
        frame["pc"] = 0
        # An "up to one" target left unchosen doesn't count: only chosen targets can all be illegal.
        frame["fizzled"] = (!specs.empty? && obj.targets.to_a.flatten.any? && targets.flatten.none?) ||
                           !intervening_if_holds?(obj, ability)
        frame["ctx"] = { "controller" => obj.controller, "source" => obj.ability? ? obj.source : obj.id,
                         "object" => obj.id, "targets" => targets, "results" => {} }
        frame["ctx"]["linked"] = obj.memory["results"] if obj.memory.key?("results") # a delayed trigger's (CR 603.7c)
        frame["ctx"]["linked_amounts"] = obj.memory["amounts"] if obj.memory.key?("amounts") # a reflexive trigger's
        frame["ctx"].merge!(Snapshot.deep_copy(obj.memory["departed"])) if obj.memory.key?("departed") # and its LKI
      end

      # CR 400.7j / 608.2c: objects an effect moves or creates, so later effects can refer to them
      # ("the card exiled this way"). Kept per effect in the frame, so a waiting effect accumulates.
      def recording_results(frame)
        @recorded = []
        @recorded_amount = 0
        yield
      ensure
        (frame["ctx"]["results"] ||= {})[frame["pc"].to_s] = (frame["ctx"]["results"][frame["pc"].to_s] || []) + @recorded
        record_amounts!(frame) if @recorded_amount.positive?
        @recorded = @recorded_amount = nil
      end

      # How much an effect changed, e.g. life it made a player lose (CR 608.2c), per effect (see {"this_way": n}).
      def record_amounts!(frame)
        amounts = (frame["ctx"]["amounts"] ||= {})
        amounts[frame["pc"].to_s] = amounts.fetch(frame["pc"].to_s, 0) + @recorded_amount
      end

      def record_amount!(amount) = @recorded_amount &&= @recorded_amount + amount

      # Called by zone changes and token creation while an effect runs.
      def record_result!(id) = @recorded&.push(id)

      # Runs the block recording apart what it moves or creates and how much it changes (an effect of a nested
      # list with results of its own, Effects::Repeat); returns [the block's value, those objects, that amount].
      # They also count for the effect running the nested list.
      def recording_apart
        outer = @recorded
        outer_amount = @recorded_amount
        @recorded = []
        @recorded_amount = 0
        value = yield
        [value, @recorded, @recorded_amount]
      ensure
        inner = @recorded
        inner_amount = @recorded_amount
        @recorded = outer && (outer + inner)
        @recorded_amount = outer_amount && (outer_amount + inner_amount)
      end

      # The context for one effect; a modal ability's effects see only their mode's targets.
      # CR 603.4: a triggered ability whose intervening "if" is false on resolution does nothing.
      def intervening_if_holds?(obj, ability)
        return true unless obj.ability? && ability.respond_to?(:condition_met?)

        ability.condition_met?(self, obj.controller, obj.source, obj.id)
      end

      # `base` is the plan position of the first effect of this effect's list: result n is at base + n.
      # A delayed or reflexive trigger's effects see the results (and amounts) of the earlier effects of the list
      # that created it first, then their own (StackAbility.parse_effects numbers them on, CR 603.7c, 603.12).
      def effect_context(data, offset = 0, count = nil, base = 0)
        targets = count ? data["targets"][offset, count] || [] : data["targets"]
        own = data["results"] || {}
        results = Array.new([own.size - base, 0].max) { own[(base + it).to_s] || [] }
        amounts = Array.new(results.size) { data.fetch("amounts", {})[(base + it).to_s] || 0 }
        if (linked = data["linked"])
          linked_amounts = Array.new(linked.size) { data["linked_amounts"]&.[](it).to_i }
          results = linked + results
          amounts = linked_amounts + amounts
        end
        Mechanics::EffectContext.new(data["controller"], data["source"], data["object"], targets, results, amounts)
      end

      def finish_fizzle!(_frame, obj)
        emit Events::Fizzled.new(object: obj.id, card: obj.card)
        obj.ability? ? remove_stack_object!(obj.id) : move!(obj.id, :graveyard, reason: "fizzled")
        after_resolution!
      end

      def after_resolution!
        state.passes = 0
        give_priority!(state.active) # CR 117.3b
        :done
      end

      # Targets that are still legal; illegal ones become nil and are ignored (CR 608.2b).
      def legal_targets(obj, specs)
        legal = lambda { |ref, spec|
          spec&.match_for?(self, ref, obj.controller, obj.source, ctx: x_context(obj.controller, obj.source, obj)) &&
            targetable?(ref, obj.controller, obj.source, targeter: obj.source || obj.id)
        }
        (obj.targets || []).each_with_index.map do |ref, i|
          ref.is_a?(Array) ? ref.select { legal.call(it, specs[i]) } : (ref if legal.call(ref, specs[i])) # a counted slot's list
        end
      end

      def finish_resolution!(obj, frame = {})
        return remove_stack_object!(obj.id) if obj.ability?
        return unless state.stack.include?(obj.id) # it may have left the stack during resolution

        if definition(obj).permanent?
          enters = with_sunburst(obj, enters_from_answer(obj.id, frame) || {}).merge("cast" => true)
          enters = enters.merge("attached_to" => frame.dig("ctx", "targets", 0)) if aura?(obj) # CR 608.3c
          pay_entering_costs!(obj.controller, frame)
          move!(obj.id, :battlefield, controller: obj.controller, reason: "resolve", enters: enters) # CR 608.3
        elsif !put_away_spell_face!(obj) && !Mechanics::Keywords::Paradigm.resolved!(self, obj) # Engine::Faces; CR 702.192a
          move!(obj.id, :graveyard, reason: "resolve") # CR 608.2n
        end
      end

      # CR 702.44a-b: a spell with sunburst enters with a counter for each color of mana spent on it.
      def with_sunburst(obj, enters)
        counters = Mechanics::Keywords::Sunburst.entering_counters(self, obj)
        return enters if counters.empty?

        enters ||= {}
        enters.merge("counters" => enters.fetch("counters", {}).merge(counters) { |_, a, b| a + b })
      end

      # Abilities on the stack aren't cards; they simply cease to exist.
      def remove_stack_object!(id)
        remember_ability!(object(id))
        state.stack.delete(id)
        state.objects.delete(id)
      end

      # "Copy that ability" (CR 707.10) after it has left the stack: the abilities that refer to it ({"triggering":
      # "ability"}) remember it as it last existed on the stack, with its choices (CR 608.2h), to copy that.
      def remember_ability!(obj)
        refs = [obj.id, obj.memory["trigger_id"]].compact
        holders = state.stack.map { object(it).memory } + state.pending_triggers.filter_map { it["memory"] }
        holders.each do |memory|
          triggering = memory["triggering"]
          memory["ability_lki"] = obj.to_h if triggering.is_a?(Hash) && refs.include?(triggering["ability"]) && !memory.equal?(obj.memory)
        end
      end

      # The ability `memory` remembers (see #remember_ability!), as a detached object that is never stored.
      def remembered_ability(memory)
        lki = memory["ability_lki"]
        lki && Snapshot.build_object(lki)
      end
    end

    include Resolution
  end
end
