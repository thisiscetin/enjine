# frozen_string_literal: true

module Enjine
  class Engine
    # A variable number of targets for one instance of the word "target" (CR 601.2c, 115.1): "X target
    # creatures", "any number of target players", "up to two target creatures". Such a target spec fills
    # one slot of the targets list with a list of objects: the player first announces how many (a
    # choose_target_count decision, unless the number is fixed), then chooses that many different ones
    # (CR 115.3). {"target": n} then refers to each of them. The number never changes afterwards.
    module TargetCounts
      def counted_target?(spec) = spec.respond_to?(:counted?) && spec.counted?

      # The slot being filled: the open list while choosing its objects, else the next slot.
      def target_slot(ctx) = ctx["counting"] ? ctx["targets"].size - 1 : ctx["targets"].size

      # Objects already chosen for the open list (CR 115.3: each at most once).
      def open_target_group(ctx) = ctx["counting"] ? ctx["targets"].last : []

      # Asks for the next target (or how many), true while waiting; false once every slot is filled.
      def ask_targets!(ctx, specs)
        loop do
          return false if !ctx["counting"] && ctx["targets"].size >= specs.size

          spec = specs[target_slot(ctx)]
          if ctx["counting"] || !counted_target?(spec)
            ask!("kind" => "choose_target", "player" => ctx["player"], "index" => target_slot(ctx))
            return true
          end
          min, max = target_count_range(ctx, spec)
          if min != max
            ask!("kind" => "choose_target_count", "player" => ctx["player"], "index" => target_slot(ctx), "min" => min,
                 "max" => max)
            return true
          end
          start_target_group!(ctx, min)
        end
      end

      def target_count_options
        pending = state.pending
        (pending["min"]..pending["max"]).map { { type: "count", count: it } }
      end

      # CR 601.2c: the number is announced before the targets.
      def choose_target_count!(count)
        start_target_group!(casting, count)
        ask!(nil)
      end

      def start_target_group!(ctx, count)
        ctx["targets"] << []
        ctx["counting"] = count if count.positive?
      end

      # Records a chosen target: into the open list, or as the next slot.
      def add_chosen_target!(ctx, ref)
        return ctx["targets"] << ref unless ctx["counting"]

        ctx["targets"].last << ref
        ctx["counting"] -= 1
        ctx.delete("counting") if ctx["counting"].zero?
      end

      # [min, max] targets to announce: the spec's count (0 up to it with "up to"; any number with "any"),
      # never more than there are different legal targets, nor (dividing, CR 601.2d) more than the amount.
      # Too few legal targets for an exact count makes the cast illegal: only cancelling is left (CR 734.1).
      # A triggered ability can't be rewound: one whose count turns out larger than the legal targets
      # (an X only known once it is put on the stack) gets as many as there are.
      def target_count_range(ctx, spec)
        count_ctx = Mechanics::EffectContext.new(ctx["player"], ctx["source"] || ctx["object"], ctx["object"], nil, [])
        min, max = spec.count_range(self, count_ctx)
        available = target_candidates.size
        divide = casting_ability&.extras&.divide
        return [min, min] if min > available && cancellable?

        max = [max || available, available, divide].compact.min
        [[min, max].min, max]
      end

      # The fewest targets the spec needs, to tell whether it can be cast or activated now (CR 601.2c);
      # an X not announced yet counts as 0.
      def target_minimum(spec, index, source)
        return 0 if optional_target?(spec)
        return 1 unless counted_target?(spec)

        spec.count_range(self, Mechanics::EffectContext.new(index, source, nil, nil, [])).first
      end

      # Each target with the spec it was chosen for, flattening counted slots: [[ref, spec], ...].
      def target_slots(targets, specs)
        targets.each_with_index.flat_map do |ref, i|
          ref.is_a?(Array) ? ref.map { [it, specs[i]] } : [[ref, specs[i]]]
        end
      end

      # The flat list `flat` shaped like `template` (a copy keeps the number of targets, CR 707.10c).
      def regroup_targets(flat, template)
        flat = flat.dup
        template.map { it.is_a?(Array) ? flat.shift(it.size) : flat.shift }
      end
    end
    include TargetCounts
  end
end
