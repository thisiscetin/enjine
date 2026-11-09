# frozen_string_literal: true

module Enjine
  class Engine
    # Phasing (CR 702.26) isn't a zone change (702.26d): a phased-out permanent keeps its id, counters,
    # tapped status, attachments and controller. It is moved from `state.battlefield` to the pseudo-zone
    # `state.phased_out` (zone `:phased_out`), so every rule that looks at the battlefield treats it as
    # though it doesn't exist (702.26b) without knowing about phasing. `GameObject#phased_out` records
    # who controlled it as it phased out (for 502.1) and whether it phased out indirectly, attached to
    # another permanent (702.26g).
    module Phasing
      # Phases out the permanents `ids` at the same time. Auras and Equipment attached to them phase out
      # indirectly with them; one that would phase out both ways phases out indirectly (CR 702.26g-h).
      def phase_out!(ids)
        ids = ids.select { state.battlefield.include?(it) }
        indirect = ids.flat_map { attached_tree(it) }
        (ids - indirect).each do |id|
          obj = object(id)
          phase_out_one!(obj, false)
          attached_tree(id).each { phase_out_one!(object(it), true) }
        end
      end

      # Every permanent attached to `id`, and every permanent attached to those (CR 702.26g).
      def attached_tree(id)
        attachments_of(id).flat_map { [it, *attached_tree(it)] }
      end

      def phase_out_one!(obj, indirectly)
        return unless state.battlefield.delete(obj.id)

        obj.zone = :phased_out
        obj.phased_out = { "by" => obj.controller, "indirectly" => indirectly }
        state.phased_out << obj.id
        leave_combat!(obj.id) # CR 506.4: removed from combat
        end_while_source_effects!(obj.id) # CR 702.26f: "for as long as" effects can no longer see it
        emit Events::PhasedOut.new(object: obj.id, indirectly: indirectly)
      end

      # CR 502.1, 702.26a: simultaneously, the phased-in permanents with phasing that `index` controls phase
      # out, and the permanents that phased out directly under `index`'s control phase in, with whatever
      # phased out indirectly attached to them (CR 702.26g). The set phasing in is fixed first, so nothing
      # phases out and back in at once. Nothing phases in while an effect says permanents can't phase in.
      def phasing_step!(index)
        coming = phasing_in_prevented? ? [] : state.phased_out.select { phases_in_for?(object(it), index) }
        phase_out!(state.battlefield.select { object(it).controller == index && chars(it).keyword?(:phasing) })
        coming.each { phase_in!(object(it)) }
      end

      def phases_in_for?(obj, index) = obj.phased_out["by"] == index && !obj.phased_out["indirectly"]

      def phasing_in_prevented?
        state.battlefield.any? { |id| chars(id).abilities.any? { it.ability.kind == :cant_phase_in } }
      end

      # CR 702.26c, 702.26i: it phases in attached to what it was attached to if that is still on the
      # battlefield (phased in or not), else unattached; state-based actions deal with the rest.
      def phase_in!(obj)
        state.phased_out.delete(obj.id)
        indirectly = obj.phased_out["indirectly"]
        obj.zone = :battlefield
        obj.phased_out = nil
        state.battlefield << obj.id
        to = obj.attached_to
        obj.attached_to = nil if !indirectly && to && !state.battlefield.include?(to) && !state.phased_out.include?(to)
        emit Events::PhasedIn.new(object: obj.id)
        state.phased_out.select { object(it).attached_to == obj.id && object(it).phased_out["indirectly"] }
             .each { phase_in!(object(it)) }
      end
    end

    include Phasing
  end
end
