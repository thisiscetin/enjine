# frozen_string_literal: true

module Enjine
  class Engine
    # Committing a crime (CR 700.13): a player commits a crime as they cast a spell, activate an ability or put a
    # triggered ability on the stack that targets at least one opponent, a permanent, spell or ability an opponent
    # controls, or a card in an opponent's graveyard. One spell or ability is one crime, however many of its
    # targets qualify. Checked once the spell is cast, the ability activated or the trigger put on the stack with
    # its targets (Events::SpellCast, AbilityActivated, TriggerPutOnStack), so a cancelled cast is no crime; a copy
    # put on the stack (CR 707.10) or new targets chosen later (CR 115.7) aren't cast or activated, so they aren't
    # either. The turn log counts them ("crimes", amount `crimes_this_turn`), and Events::CrimeCommitted is what
    # "whenever you commit a crime" (trigger `commits_crime`) watches.
    module Crimes
      CRIME_EVENTS = [Events::SpellCast, Events::AbilityActivated, Events::TriggerPutOnStack].freeze

      # Emits the crime that `event` (a spell cast, an ability activated or a trigger put on the stack) commits.
      def check_crime!(event)
        return unless CRIME_EVENTS.include?(event.class)

        index = names.index(event.player)
        return unless index && Array(event.targets).flatten.compact.any? { crime_target?(index, it) }

        emit Events::CrimeCommitted.new(player: event.player, object: event.object)
      end

      # CR 700.13: an opponent, a permanent, spell or ability an opponent controls, or a card in an opponent's graveyard.
      def crime_target?(index, ref)
        player = Mechanics::Filters.player_index(self, ref)
        return player != index unless player.nil?

        obj = state.objects[ref] or return false
        case obj.zone
        when :battlefield, :stack then obj.controller != index
        when :graveyard then obj.owner != index
        else false
        end
      end
    end
    include Crimes
  end

  module Events
    # CR 700.13: `player` committed a crime with the spell or ability `object`.
    CrimeCommitted = define(:crime_committed, :player, :object)
  end
end
