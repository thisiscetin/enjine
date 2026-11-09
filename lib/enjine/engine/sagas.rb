# frozen_string_literal: true

module Enjine
  class Engine
    # Sagas (CR 715, 704.5s): lore counters, chapter abilities and sacrificing a finished Saga.
    module Sagas
      # Chapter numbers of a permanent's chapter abilities (CR 715.2).
      def chapter_numbers(id) = chars(id).abilities.filter_map { it.ability.chapter if it.ability.respond_to?(:chapter) }

      # CR 715.3c / 505.4: as the precombat main phase begins, the active player puts a lore counter on
      # each Saga they control with one or more chapter abilities (a turn-based action).
      def add_lore_counters!(index)
        sagas = state.battlefield.select do |id|
          object(id).controller == index && chars(id).subtypes.include?(:saga) && !chapter_numbers(id).empty?
        end
        sagas.each { add_counters!(object(it), "lore", 1) }
      end

      # CR 715.4 / 704.5s: a Saga whose lore counters reach its final chapter number (CR 715.2d) is
      # sacrificed, unless it's the source of a chapter ability that has triggered but not left the stack.
      def saga_complete?(obj)
        c = chars(obj)
        return false unless c.subtypes.include?(:saga)

        chapters = chapter_numbers(obj.id)
        !chapters.empty? && obj.counters.fetch("lore", 0) >= chapters.max && !chapter_pending?(obj)
      end

      def chapter_pending?(obj)
        chapter = ->(card, ref) { catalog.fetch(card).ability(ref).respond_to?(:chapter) }
        state.pending_triggers.any? { it["source"] == obj.id && chapter.call(it["card"], it["ability"]) } ||
          state.stack.any? do |id|
            stacked = object(id)
            stacked.ability? && stacked.source == obj.id && chapter.call(stacked.card, stacked.ability)
          end
      end
    end

    include Sagas
  end
end
