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

      # ---- permanents an effect puts onto the battlefield (CR 614.12, 614.12a) ----------------

      # Before any of them enters, the player who will control each permanent makes its "as this enters"
      # choice, one permanent at a time. `entries`: [[object id or token key, controller], ...]. Answers
      # stay in the effect's locals (Engine#enter_choice!), so the effect resumes after each. :wait while asking.
      def ask_entering_choices!(locals, entries)
        answers = locals["entering"] ||= {}
        id, controller = entries.find { |ref, _| !answers.key?(ref) && entering_choice(ref) }
        return nil unless id

        token = state.objects.key?(id) ? {} : { "card" => token_to_create(id).id }
        ask!({ "kind" => "enter_choice", "player" => controller, "object" => id, "effect" => true }.merge(token))
        :wait
      end

      # Puts cards onto the battlefield at the same time: replacement effects for all of them are determined
      # before any enters (CR 614.12), with the choices asked by #ask_entering_choices!. `entries`:
      # [[id, controller, enters]]. Returns the new permanents.
      def enter_battlefield!(locals, entries, reason:)
        plans = entries.map do |id, controller, enters|
          plan_move(id, :battlefield, reason: reason, controller: controller,
                                      enters: with_entering_answer(locals, id, controller, enters))
        end
        plans.compact.map { execute_zone_change!(it) }
      end

      # The entering status `enters` plus what the "as this enters" answer for `id` adds (a memory, tapped);
      # a life payment chosen is paid now, as it enters (CR 119.4).
      def with_entering_answer(locals, id, controller, enters)
        answer = locals.fetch("entering", {})[id] or return enters
        pay_entering_life!(controller, "enter" => answer)
        extra = entering_status(entering_choice(id), answer) or return enters
        (enters || {}).merge(extra) do |key, mine, theirs|
          next mine || theirs if key == "tapped" # "enters tapped" from the effect stays

          mine.is_a?(Hash) ? mine.merge(theirs) : theirs
        end
      end

      # The options of a pending enter_choice. Several permanents entering at once can't be given choices
      # whose combined life payments are more than the player has (CR 614.12b).
      def entering_options(pending)
        options = entering_choice(pending["object"]).options(self, pending["player"])
        return options unless pending["effect"]

        spent = answering_locals.fetch("entering", {}).values.sum do
          it["player"] == pending["player"] && it["type"] == "pay_life" ? it["life"] : 0
        end
        options.reject { it[:type] == "pay_life" && it[:life] > player(pending["player"]).life - spent }
      end

      # A token an effect is about to create, named before it exists ("new_token:<card>:<n>") so its "as
      # this enters" choice can be asked first (CR 614.12, 111.1).
      def token_key(definition, index) = "new_token:#{definition.id}:#{index}"
      def token_to_create(key) = catalog.fetch(key.to_s.split(":")[1].to_s)

      def resolving_ability(obj)
        obj.ability? ? stack_ability(obj) : definition(obj).spell_ability
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

          frame["pc"] += 1
        end
        if !obj.ability? && definition(obj).permanent? && entering_choice(obj.id) && !frame["enter"]
          return ask_enter_choice!(obj.id, obj.controller) # CR 614.12: decided before it enters
        end

        emit Events::Resolved.new(object: obj.id, card: obj.card, kind: obj.kind)
        finish_resolution!(obj, frame)
        after_resolution!
      end

      # CR 608.2b: targets are checked once, as resolution begins.
      def start_resolution!(frame, obj, ability)
        specs = ability&.targets_for(obj.modes || [], kicked: obj.memory["kicked"]) || []
        targets = legal_targets(obj, specs)
        frame["pc"] = 0
        # An "up to one" target left unchosen doesn't count: only chosen targets can all be illegal.
        frame["fizzled"] = (!specs.empty? && obj.targets.to_a.flatten.any? && targets.flatten.none?) ||
                           !intervening_if_holds?(obj, ability)
        frame["ctx"] = { "controller" => obj.controller, "source" => obj.ability? ? obj.source : obj.id,
                         "object" => obj.id, "targets" => targets, "results" => {} }
        frame["ctx"]["linked"] = obj.memory["results"] if obj.memory.key?("results") # a delayed trigger's (CR 603.7c)
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

      # The context for one effect; a modal ability's effects see only their mode's targets.
      # CR 603.4: a triggered ability whose intervening "if" is false on resolution does nothing.
      def intervening_if_holds?(obj, ability)
        return true unless obj.ability? && ability.respond_to?(:condition_met?)

        ability.condition_met?(self, obj.controller, obj.source, obj.id)
      end

      # `base` is the plan position of the first effect of this effect's list: result n is at base + n.
      # A delayed trigger's effects see the results of the list that created it instead.
      def effect_context(data, offset = 0, count = nil, base = 0)
        targets = count ? data["targets"][offset, count] || [] : data["targets"]
        own = data["results"] || {}
        results = data["linked"] || Array.new([own.size - base, 0].max) { own[(base + it).to_s] || [] }
        amounts = Array.new(results.size) { data.fetch("amounts", {})[(base + it).to_s] || 0 }
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
        legal = ->(ref, spec) { spec&.match_for?(self, ref, obj.controller, obj.source) && targetable?(ref, obj.controller, obj.source) }
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
          pay_entering_life!(obj.controller, frame)
          move!(obj.id, :battlefield, controller: obj.controller, reason: "resolve", enters: enters) # CR 608.3
        elsif !put_away_spell_face!(obj) # an Adventure or Omen (Engine::Faces)
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
        state.stack.delete(id)
        state.objects.delete(id)
      end
    end
    include Resolution
  end
end
