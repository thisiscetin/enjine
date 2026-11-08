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
          effect, offset, count = plan[frame["pc"]]
          ctx = effect_context(frame["ctx"], offset, count)
          locals = (frame["locals"][frame["pc"].to_s] ||= {})
          return :wait if effect.run(self, ctx, locals) == :wait

          frame["pc"] += 1
        end
        emit Events::Resolved.new(object: obj.id, card: obj.card, kind: obj.kind)
        finish_resolution!(obj)
        after_resolution!
      end

      # CR 608.2b: targets are checked once, as resolution begins.
      def start_resolution!(frame, obj, ability)
        specs = ability&.targets_for(obj.modes || []) || []
        targets = legal_targets(obj, specs)
        frame["pc"] = 0
        frame["fizzled"] = !specs.empty? && targets.none?
        frame["ctx"] = { "controller" => obj.controller, "source" => obj.ability? ? obj.source : obj.id,
                         "object" => obj.id, "targets" => targets }
      end

      # The context for one effect; a modal ability's effects see only their mode's targets.
      def effect_context(data, offset = 0, count = nil)
        targets = count ? data["targets"][offset, count] || [] : data["targets"]
        Mechanics::EffectContext.new(data["controller"], data["source"], data["object"], targets)
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
        (obj.targets || []).each_with_index.map do |ref, i|
          ref if specs[i]&.match?(self, ref, obj.controller) && targetable?(ref, obj.controller)
        end
      end

      def finish_resolution!(obj)
        return remove_stack_object!(obj.id) if obj.ability?
        return unless state.stack.include?(obj.id) # it may have left the stack during resolution

        if definition(obj).permanent?
          move!(obj.id, :battlefield, controller: obj.controller, reason: "resolve") # CR 608.3
        else
          move!(obj.id, :graveyard, reason: "resolve") # CR 608.2n
        end
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
