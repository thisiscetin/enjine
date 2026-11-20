# frozen_string_literal: true

module Enjine
  class Engine
    # The Commander variant (CR 903) for two players: each player's commander starts in the command zone
    # (903.6), may be cast from there for {2} more per earlier cast (903.8), may return to the command zone
    # when it would go elsewhere (903.9), and 21 combat damage from one commander loses the game (903.10a).
    #
    # A commander is a *card*, not an object (CR 903.3): it stays one through zone changes, but a token or a
    # copy of it is not. So nothing marks the object; `commander?` asks whose card it really is.
    #
    # State: `State#commanders` (each player's commander card id), PlayerState#commander_casts (times cast from
    # the command zone) and #commander_damage ({card id => combat damage dealt to them}), and
    # State#commander_returns (see #note_commander_move!).
    module Commander
      TAX = 2 # CR 903.8: {2} more for each previous cast from the command zone
      DAMAGE_LOSS = 21 # CR 903.10a
      # Zones a commander may be sent back from (CR 903.9a graveyard and exile, 903.9b hand and library).
      RETURNABLE_ZONES = %i[graveyard exile hand library].freeze

      # ---- who is a commander ---------------------------------------------------------------------

      # The card id of `obj` if it is its owner's commander. A card face counts as its card (a transformed
      # commander is still one); a token, a copy and a card the object copies are not (CR 903.3 examples).
      def commander?(obj)
        return false unless state.format.commander? && obj.kind == "card" && !obj.memory["copy"]

        own = own_card(obj).split(CardDefinition::FACE_SEPARATOR).first
        own == state.commanders[obj.owner] && !token?(obj)
      end

      # CR 903.6: each player puts their commander face up into the command zone, before libraries are shuffled.
      def place_commanders!
        state.commanders.each_with_index do |card, owner|
          state.command << create_object(card, owner, :command).id if card
        end
      end

      # The commander `index` has waiting in the command zone, if it's there.
      def commander_in_command_zone(index)
        state.command.find { state.objects[it]&.owner == index && commander?(object(it)) }
      end

      # ---- casting (CR 903.8) -----------------------------------------------------------------------

      def commander_casts(index) = player(index).commander_casts.to_i

      # The extra generic mana the next cast of `index`'s commander from the command zone costs.
      def commander_tax(index) = TAX * commander_casts(index)

      # Command-zone cards `index` may try to cast: their commander.
      def commander_candidates(index) = [commander_in_command_zone(index)].compact

      # The way to cast a commander from the command zone (see Engine::Permissions): its cost includes the tax.
      def command_methods(index, obj)
        return [] unless obj.zone == :command && obj.owner == index && commander?(obj)

        [{ "via" => "command", "play" => "cast", "cost_increase" => commander_tax(index) }]
      end

      # As a spell becomes cast from the command zone (CR 601.2i): it counts toward the next tax (CR 903.8).
      def record_commander_cast!(index, method)
        return unless method && method["via"] == "command"

        player(index).commander_casts = commander_casts(index) + 1
      end

      # ---- 21 combat damage (CR 903.10a) ----------------------------------------------------------

      # Combat damage `source` dealt to player `index`: counted against the commander it came from.
      def note_commander_damage!(source, index, amount)
        obj = state.objects[source]
        return unless obj && commander?(obj)

        total = (player(index).commander_damage ||= {})
        card = state.commanders[obj.owner]
        total[card] = total.fetch(card, 0) + amount
      end

      def loses_to_commander_damage?(index)
        (player(index).commander_damage || {}).values.any? { it >= DAMAGE_LOSS }
      end

      # ---- returning to the command zone (CR 903.9) -------------------------------------------------

      # A commander that moved to a graveyard, exile, hand or library: its owner may send it to the command
      # zone before anyone gets priority (CR 903.9a is a state-based action; 903.9b a replacement effect, which
      # the engine applies right after the move, since a replacement can't ask a player).
      def note_commander_move!(fresh)
        state.commander_returns << fresh.id if RETURNABLE_ZONES.include?(fresh.zone) && commander?(fresh)
      end

      # Before priority: the next commander waiting to be sent back asks its owner (a frame, like the
      # legend rule). Returns true when it started one.
      def commander_choice_first!(index)
        return false if state.frames.any? { it["type"] == "commander_zone" }

        state.commander_returns.select! { state.objects.key?(it) } # moved on since
        id = state.commander_returns.first or return false
        state.frames << { "type" => "commander_zone", "then" => index, "object" => id }
        ask!(nil)
        true
      end

      def step_commander_zone!(frame)
        id = frame["object"]
        unless frame.key?("choice")
          ask!("kind" => "commander_zone", "player" => object(id).owner, "object" => id)
          return :wait
        end
        state.commander_returns.delete(id)
        move!(id, :command, reason: "commander") if frame["choice"] == "command" && state.objects.key?(id)
        give_priority!(frame["then"])
        :done
      end

      def choose_commander_zone!(to_command_zone)
        state.frames.rfind { it["type"] == "commander_zone" }["choice"] = to_command_zone ? "command" : "stay"
        ask!(nil)
      end
    end

    include Commander
  end
end
