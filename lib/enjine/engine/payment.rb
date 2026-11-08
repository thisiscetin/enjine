# frozen_string_literal: true

module Enjine
  class Engine
    # Paying mana one decision at a time (CR 601.2g-h, 605.3a), shared by casting/activating (a
    # "cast" frame) and costs paid while a spell or ability resolves (a "pay" frame, CR 118.12).
    #
    # The frame holds what is left to pay ("remaining": generic, one key per color, and "hybrid":
    # the hybrid symbols still unpaid, CR 107.4e), the pool before payment started ("pool") and the
    # sources tapped for it ("tapped"), so an unfinished payment can be rewound (CR 733.1). Once a
    # mana ability with a cost other than {T} has been activated (a Treasure's sacrifice), the payment
    # is "irreversible": it can't be cancelled any more, and only choices that keep the rest payable
    # are offered, so the player can't get stuck.
    module Payment
      # The payment in progress: the top frame (a cast or a pay frame while a casting decision is pending).
      def payment = state.frames.last

      # Whether the process on top can still be rewound with a "cancel" option.
      def cancellable?
        frame = payment
        !frame.nil? && frame["kind"] != "trigger" && !frame["irreversible"]
      end

      # ---- the remaining cost ---------------------------------------------------------

      def remaining_hash(cost)
        rem = { "generic" => cost&.generic.to_i }
        cost&.colored&.each { |color, n| rem[color.to_s] = n }
        rem["hybrid"] = cost.hybrid.map { |pair| pair.map(&:to_s) } unless cost.nil? || cost.hybrid.empty?
        rem
      end

      def remaining_cost(rem)
        colored = rem.except("generic", "hybrid").transform_keys(&:to_sym).reject { |_, n| n.zero? }
        Mana::Cost.new(generic: rem["generic"], colored: colored,
                       hybrid: rem.fetch("hybrid", []).map { |pair| pair.map(&:to_sym) })
      end

      def remaining_left?(rem) = remaining_cost(rem).mana_value.positive?

      # What is still to pay, as mana symbols.
      def remaining_text(frame = payment) = remaining_cost(frame["remaining"]).to_s

      # ---- paying from the pool ----------------------------------------------------------

      # Mana types in the pool that can pay part of the remaining cost (CR 601.2h).
      def payable_mana_types
        frame = payment
        player(frame["player"]).mana_pool.filter_map do |type, n|
          next unless n.positive?

          # Once a mana can go somewhere, some place keeps the rest payable (pay_mana! picks it), so no
          # pool mana can strand an irreversible payment.
          type.to_s unless pay_slots(frame["remaining"], type.to_s).empty?
        end
      end

      # Where one mana of `type` can go: its own colored symbol, a hybrid symbol that includes it,
      # or generic mana. [[:color], [:hybrid, i], [:generic]].
      def pay_slots(rem, type)
        slots = []
        slots << [:color] if rem.fetch(type, 0).positive?
        rem.fetch("hybrid", []).each_with_index { |pair, i| slots << [:hybrid, i] if pair.include?(type) }
        slots << [:generic] if rem["generic"].positive?
        slots
      end

      # Spends one mana; it pays the first slot that keeps the rest payable (a hybrid symbol the other
      # color could also pay waits for it), deterministically.
      def pay_mana!(type)
        frame = payment
        slots = pay_slots(frame["remaining"], type)
        slot = slots.find { completable_after_paying?(frame, type, it) } || slots.first
        player(frame["player"]).mana_pool[type.to_sym] -= 1
        frame["remaining"] = after_paying(frame["remaining"], type, slot)
        (frame["spent"] ||= []) << type # what was spent matters later (sunburst, CR 702.44a)
        emit Events::ManaPaid.new(player: name(frame["player"]), mana: "{#{type}}", object: frame["object"])
        ask!(nil)
      end

      def after_paying(rem, type, slot)
        rem = Snapshot.deep_copy(rem)
        case slot.first
        when :color then rem[type] -= 1
        when :hybrid then rem["hybrid"].delete_at(slot.last)
        else rem["generic"] -= 1
        end
        rem.delete("hybrid") if rem["hybrid"] && rem["hybrid"].empty?
        rem
      end

      def completable_after_paying?(frame, type, slot)
        pool = player(frame["player"]).mana_pool.dup
        pool[type.to_sym] -= 1
        payable_with?(frame["player"], remaining_cost(after_paying(frame["remaining"], type, slot)), pool,
                      payment_reserved(frame))
      end

      # ---- mana abilities during payment (CR 601.2g, 605.3a) ---------------------------------

      # Mana sources usable during payment: not a source the spell or ability still needs for one of
      # its own costs ({T}, or a cost that sacrifices or exiles it), unless the mana ability only taps it
      # and the cost doesn't.
      def payment_sources
        frame = payment
        sources = all_mana_sources(frame["player"]).reject { |id, ref| reserved_for_cost?(frame, id, ref) }
        sources.select do |id, ref|
          (!frame["irreversible"] && !irreversible_mana_ability?(id, ref)) || completable_after_activating?(frame, id, ref)
        end
      end

      # A mana ability whose costs include more than {T} (a sacrifice, life, a discard) can't be undone.
      def irreversible_mana_ability?(id, ref) = chars(id).ability(ref).costs.any? { !it.is_a?(Mechanics::Costs::Tap) }

      def reserved_for_cost?(frame, id, ref)
        return true if id == payment_excluded_source(frame)

        payment_reserved(frame).include?(id) && chars(id).ability(ref).costs.any? { !it.is_a?(Mechanics::Costs::Tap) }
      end

      # Permanents a cost of the spell or ability will still use: its source when it has a non-mana cost
      # about itself, and permanents chosen for a cost paid when it becomes cast (CR 601.2h).
      def payment_reserved(frame)
        return [] unless frame["type"] == "cast"

        reserved = (frame["paid"] || []).map { it["object"] }
        reserved << frame["source"] if frame["kind"] == "ability" && casting_ability.costs.any? { it.respond_to?(:uses_source?) }
        reserved
      end

      def completable_after_activating?(frame, id, ref)
        pool = player(frame["player"]).mana_pool.dup
        chars(id).ability(ref).produce.each { pool[it] += 1 }
        payable_with?(frame["player"], remaining_cost(frame["remaining"]), pool, payment_reserved(frame) + [id])
      end

      # CR 605.3: activating a mana ability while paying. One whose costs include more than {T} (a
      # sacrifice, life, a discard) can't be undone, so the payment stops being cancellable.
      def tap_for_payment!(id, ability_ref)
        frame = payment
        frame["irreversible"] = true if irreversible_mana_ability?(id, ability_ref)
        activate_mana_ability!(frame["player"], id, ability_ref)
        frame["tapped"] << id
        ask!(nil)
      end

      # Whether `cost` can be paid from `pool` plus the player's untapped sources, minus `excluded`.
      def payable_with?(index, cost, pool, excluded)
        return true if cost.mana_value.zero?

        units = pool.flat_map { |type, n| Array.new([n, 0].max) { [type] } } + source_units(index, excluded)
        units.size >= cost.mana_value && match_colored(cost.requirements, units)
      end

      # ---- cancelling ----------------------------------------------------------------------

      # The "cancel" option of a payment decision: rewinds a cast, or declines a resolution payment.
      def cancel_payment!
        payment["type"] == "cast" ? cancel_casting! : decline_payment!
      end

      # Undoes the mana abilities activated for the payment (CR 733.1): untaps their sources and restores
      # the pool. Abilities that triggered meanwhile didn't trigger (CR 733.1).
      def rewind_payment!(frame)
        frame["tapped"].select { state.objects.key?(it) }.each do |id|
          object(id).tapped = false
          emit Events::Untapped.new(object: id)
        end
        player(frame["player"]).mana_pool = Mana::TYPES.to_h { |t| [t, frame["pool"].fetch(t.to_s, 0)] }
        state.pending_triggers.select! { frame["triggers_before"].include?(it["id"]) }
      end

      # ---- countering (CR 701.6) ----------------------------------------------------------------

      # CR 701.6a: a countered spell goes to its owner's graveyard; a countered ability ceases to exist.
      # "This spell can't be countered" wins (CR 101.2). Returns whether it was countered.
      def counter!(id)
        obj = object(id)
        return false if !obj.ability? && chars(obj).keyword?(:cant_be_countered)

        if obj.ability?
          emit Events::AbilityCountered.new(object: id, card: obj.card, source: obj.source)
          remove_stack_object!(id)
        else
          move!(id, :graveyard, reason: "countered")
        end
        true
      end

      # ---- paying while resolving (CR 118.12) -------------------------------------------------

      # Starts paying `cost` for an effect that is resolving; Effects::Payment learns the outcome as an
      # answer ("paid" or "declined") when the pay frame is done.
      def begin_payment!(index, cost, object)
        state.frames << { "type" => "pay", "player" => index, "object" => object, "remaining" => remaining_hash(cost),
                          "pool" => player(index).mana_pool.transform_keys(&:to_s), "tapped" => [],
                          "triggers_before" => state.pending_triggers.map { it["id"] } }
        ask!(nil)
      end

      def continue_payment!(frame)
        if remaining_left?(frame["remaining"])
          ask!("kind" => "pay_cost", "player" => frame["player"], "remaining" => remaining_text(frame))
          return :wait
        end
        finish_payment!(frame, "paid")
      end

      def decline_payment!
        frame = payment
        rewind_payment!(frame)
        finish_payment!(frame, "declined")
        state.frames.delete(frame)
        ask!(nil)
      end

      def finish_payment!(frame, outcome)
        emit Events::PaymentFinished.new(player: name(frame["player"]), object: frame["object"], outcome: outcome)
        resolving = state.frames.rfind { it["type"] == "resolve" }
        locals = resolving["locals"][resolving["pc"].to_s]
        locals = locals["child"] while locals["child"]
        (locals["answers"] ||= []) << { "type" => outcome }
        :done
      end
    end
    include Payment
  end

  module Events
    PaymentFinished = define(:payment_finished, :player, :object, :outcome) # CR 118.12: paid or declined
    AbilityCountered = define(:ability_countered, :object, :card, :source) # CR 701.6a
  end

  module Frames
    # Paying a cost while a spell or ability resolves (CR 118.12, 701.6), e.g. "counter it unless its
    # controller pays {2}". The payer may activate mana abilities (CR 605.3a).
    class Pay < Base
      def self.step(engine, frame) = engine.continue_payment!(frame)
      def self.decisions = %w[pay_cost]
    end
    register("pay", Pay)
  end
end
