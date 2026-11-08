# frozen_string_literal: true

module Enjine
  class Engine
    # Resolving the top object of the stack (CR 608).
    module Resolution
      def resolve_top!
        id = state.stack.first
        obj = object(id)
        ability = obj.ability? ? definition(obj).abilities[obj.ability] : definition(obj).spell_ability
        specs = ability&.targets || []
        targets = legal_targets(obj, specs)

        if !specs.empty? && targets.none? # CR 608.2b: every target illegal -> it doesn't resolve
          emit Events::Fizzled.new(object: id, card: obj.card)
          obj.ability? ? remove_stack_object!(id) : move!(id, :graveyard, reason: "fizzled")
        else
          ctx = Mechanics::EffectContext.new(obj.controller, obj.ability? ? obj.source : id, id, targets)
          ability&.effects&.each { it.apply(self, ctx) } # CR 608.2c: in order
          emit Events::Resolved.new(object: id, card: obj.card, kind: obj.kind)
          finish_resolution!(obj)
        end
        state.passes = 0
        give_priority!(state.active) # CR 117.3b
      end

      # Targets that are still legal; illegal ones become nil and are ignored (CR 608.2b).
      def legal_targets(obj, specs)
        (obj.targets || []).each_with_index.map do |ref, i|
          ref if specs[i]&.match?(self, ref, obj.controller)
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
