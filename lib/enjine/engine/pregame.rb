# frozen_string_literal: true

module Enjine
  class Engine
    # Starting the game (CR 103): choosing who plays first, mulligans (London mulligan,
    # CR 103.5) and putting cards on the bottom.
    module Pregame
      def start!
        state.decklists.each_with_index do |list, owner|
          list.each { |card| state.players[owner].library << create_object(card, owner, :library).id }
        end
        emit Events::GameStarted.new(players: names, seed: state.seed)
        winner = state.rng.rand(state.players.size)
        emit Events::DieRolled.new(winner: name(winner))
        ask!("kind" => "play_or_draw", "player" => winner)
      end

      # CR 103.1-103.4: starting player chosen, libraries shuffled, opening hands drawn.
      def choose_starting_player!(chooser, play)
        starting = play ? chooser : state.opponent(chooser)
        state.starting_player = starting
        emit Events::StartingPlayerChosen.new(chooser: name(chooser), choice: play ? "play" : "draw",
                                              starting_player: name(starting))
        turn_order.each do |i|
          shuffle_library!(i)
          HAND_SIZE.times { draw!(i) }
        end
        ask!("kind" => "mulligan", "player" => starting)
      end

      # Player indexes in turn order, starting with the starting player.
      def turn_order
        first = state.starting_player || 0
        Array.new(state.players.size) { |i| (first + i) % state.players.size }
      end

      # CR 103.5 (London mulligan): players declare in turn order, then all mulligans happen at once.
      def declare_mulligan!(index, choice)
        player(index).mulligan_choice = choice
        emit Events::MulliganDeclared.new(player: name(index), choice: choice)
        undecided = turn_order.find { |i| !player(i).kept && player(i).mulligan_choice.nil? }
        return ask!("kind" => "mulligan", "player" => undecided) if undecided

        resolve_mulligan_round!
      end

      # CR 103.5: all declared mulligans happen at the same time. Taking a mulligan is:
      # shuffle the hand away, draw a new hand, then put N cards (N = mulligans taken so
      # far) on the bottom. Only then does the next round of declarations start.
      def resolve_mulligan_round!
        turn_order.each do |i|
          pl = player(i)
          if pl.mulligan_choice == "keep"
            pl.kept = true
            emit Events::HandKept.new(player: pl.name, mulligans: pl.mulligans)
          elsif pl.mulligan_choice == "mulligan"
            take_mulligan!(i)
          end
          pl.mulligan_choice = nil
        end
        next_bottom_or_declaration!
      end

      def take_mulligan!(index)
        pl = player(index)
        pl.mulligans += 1
        pl.hand.dup.each { |id| move!(id, :library, reason: "mulligan") }
        shuffle_library!(index)
        HAND_SIZE.times { draw!(index) }
        emit Events::MulliganTaken.new(player: pl.name, mulligans: pl.mulligans)
      end

      # Bottoms owed from this round's mulligans (in turn order), then the next round of
      # declarations, then the first turn.
      def next_bottom_or_declaration!
        index = turn_order.find { |i| bottom_remaining(i).positive? }
        return ask!("kind" => "bottom", "player" => index, "count" => bottom_remaining(index)) if index

        next_player = turn_order.find { |i| !player(i).kept }
        return ask!("kind" => "mulligan", "player" => next_player) if next_player

        ask!(nil)
        begin_turn!(state.starting_player)
        advance!
      end

      def bottom_remaining(index)
        pl = player(index)
        [pl.hand.size - (HAND_SIZE - pl.mulligans), 0].max
      end
    end

    include Pregame
  end
end
