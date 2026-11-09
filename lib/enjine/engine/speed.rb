# frozen_string_literal: true

module Enjine
  class Engine
    # Speed (CR 702.179) and max speed (CR 702.178). A player has no speed (PlayerState#speed nil) until
    # start your engines! gives them 1 (CR 702.179a-b, a state-based action); it then rises to at most 4.
    module Speed
      MAX_SPEED = 4
      SPEED_ABILITY = "keyword:start_your_engines"

      # CR 702.179f: a player without speed has speed 0 for effects that refer to it.
      def speed(index) = player(index).speed.to_i

      # CR 702.179e: max speed is speed 4.
      def max_speed?(index) = speed(index) >= MAX_SPEED

      # CR 702.179c: a player without speed who is told to increase it gets that value. Never above 4.
      def increase_speed!(index, amount)
        set_speed!(index, [speed(index) + amount, MAX_SPEED].min)
      end

      def set_speed!(index, value)
        pl = player(index)
        from = pl.speed
        return if from == value

        pl.speed = value
        emit Events::SpeedChanged.new(player: name(index), from: from, to: value)
      end

      # CR 704.5aa / 702.179a: a player who controls a permanent with start your engines! and has no speed gets
      # speed 1. Returns true when a player's speed was set (state-based actions are checked again).
      def start_engines!
        return false unless speed_card

        started = state.players.each_index.select do |i|
          player(i).speed.nil? && state.battlefield.any? do |id|
            obj = object(id)
            obj.controller == i && chars(obj).keyword?(:start_your_engines)
          end
        end
        started.each { set_speed!(it, 1) }
        !started.empty?
      end

      # CR 702.179d: "Whenever one or more opponents lose life during your turn, if your speed is less than 4,
      # your speed increases by 1. This ability triggers only once each turn." It has no source; it is put on the
      # stack as the start your engines! keyword ability of a card in the game (its text, not its source).
      def watch_speed!(event)
        return unless event.is_a?(Events::LifeChanged) && event.loss.positive? && speed_card

        index = state.active
        return if index.nil? || names.index(event.player) == index
        return unless (1...MAX_SPEED).cover?(speed(index)) # has speed (CR 702.179d); the intervening "if" (CR 603.4)

        log = turn_log(index)
        return if log["speed_triggered"]

        log["speed_triggered"] = true
        queue_pending_trigger!({ "id" => nil, "card" => speed_card_of(index), "controller" => index,
                                 "ability" => SPEED_ABILITY }, event, {})
      end

      # The card whose start your engines! keyword ability stands for the speed trigger: one the player controls
      # if any (for display only: the ability has no source), else any card in the game with the keyword.
      def speed_card_of(index)
        mine = state.battlefield.find do |id|
          obj = object(id)
          obj.controller == index && catalog.fetch(obj.card).keyword?(:start_your_engines)
        end
        mine ? object(mine).card : speed_card
      end

      # A card in this game with start your engines! (whose keyword ability holds the speed trigger), or nil.
      def speed_card
        @speed_card = catalog.find { it.keyword?(:start_your_engines) }&.id unless defined?(@speed_card)
        @speed_card
      end

      # Max speed abilities that apply to `obj`: those of its card while `index` (its controller, or its owner
      # off the battlefield, CR 702.178b) has max speed.
      def active_max_speed(obj, index)
        return EMPTY_ABILITIES unless max_speed?(index)

        catalog.fetch(obj.card).ability_instances.select { it.ability.kind == :max_speed }
      end
      EMPTY_ABILITIES = [].freeze

      # A card outside the battlefield has what its max speed abilities grant while its owner has max speed
      # (CR 702.178b): e.g. "Max speed — {3}, Exile this card from your graveyard: Draw a card."
      def with_max_speed(obj, base)
        return base if obj.ability?

        symbols = active_max_speed(obj, obj.owner)
        return base if symbols.empty?

        defn = catalog.fetch(obj.card)
        base.with(abilities: (base.abilities + symbols.flat_map { defn.nested_instances(it.ref) }).freeze,
                  keywords: (base.keywords | symbols.flat_map { it.ability.keywords }).freeze)
      end
    end
    include Speed
  end
end
