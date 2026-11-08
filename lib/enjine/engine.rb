# frozen_string_literal: true

module Enjine
  # The rules state machine.
  #
  # No Ruby call stack ever holds game progress: everything lives in State, so a
  # game can be exported at any decision and resumed elsewhere. #advance! runs the
  # game forward until a player must decide something (state.pending) or the game ends.
  class Engine
    HAND_SIZE = 7
    MAX_MULLIGANS = 7

    attr_accessor :state
    attr_reader :catalog

    def initialize(catalog, state, &emit)
      @catalog = catalog
      @state = state
      @emit = emit
    end

    def emit(event)
      touch! if Characteristics::LAYER_EVENTS.include?(event.class)
      @emit.call(event)
    end

    def name(index) = state.players[index].name
    def names = state.players.map(&:name)
    def player(index) = state.players[index]
    def active_player = state.players[state.active]
    def definition(object) = catalog.fetch(object.card)
    def object(id) = state.objects.fetch(id)
    def ask!(pending) = state.pending = pending
    def step = Steps.fetch(state.step)
    def attackers = state.attackers

    # ---- pregame (CR 103) -------------------------------------------------

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

    # ---- turn structure (CR 500) --------------------------------------------

    def begin_turn!(index)
      state.turn += 1
      state.active = index
      state.players.each { it.lands_played = 0 }
      emit Events::TurnBegan.new(turn: state.turn, active: name(index))
      enter_step!(:untap)
    end

    def enter_step!(step_name)
      state.step = step_name
      state.step_state = "begin"
      state.passes = 0
      state.priority = nil
    end

    # Runs the game forward until a decision is pending or the game is over.
    def advance!
      until state.pending || state.over?
        if (frame = state.frames.last)
          step_frame!(frame)
          next
        end
        break if state.step.nil?

        case state.step_state
        when "begin"
          state.step_state = "active"
          emit Events::StepBegan.new(turn: state.turn, step: state.step.to_s, phase: step.phase.to_s)
          step.begin(self)
        when "done" then next_step!
        else raise Error, "engine stalled in #{state.step} (#{state.step_state}) with no pending decision"
        end
      end
    end

    # Steps the innermost in-progress process (see Enjine::Frames).
    def step_frame!(frame)
      result = Frames.fetch(frame["type"]).step(self, frame)
      state.frames.delete_at(state.frames.rindex { it.equal?(frame) }) if result == :done && state.frames.include?(frame)
    end

    # Called once a step's turn-based actions (and any decisions they needed) are complete.
    def turn_based_actions_done!
      step.finish(self)
      if step.priority?
        give_priority!(state.active)
      else
        ask!(nil)
        state.step_state = "done"
      end
    end

    # CR 500.4: mana empties between steps. CR 500.1: proceed to the next step / turn.
    def next_step!
      empty_mana_pools!
      end_combat! if state.step == :end_of_combat # CR 511.3
      index = Steps.index(state.step) + 1
      index += 1 while index < Steps::ORDER.size && Steps::ORDER[index].skip?(self)
      if index >= Steps::ORDER.size
        begin_turn!(state.opponent(state.active))
      else
        enter_step!(Steps::ORDER[index].name)
      end
    end

    # ---- priority (CR 117) ----------------------------------------------------

    # CR 117.5: state-based actions are checked whenever a player would receive priority.
    def give_priority!(index)
      check_state_based_actions!
      return if state.over?

      state.priority = index
      ask!("kind" => "priority", "player" => index)
    end

    # Any action other than passing resets the "pass in succession" count (CR 117.4).
    def action_taken!(index)
      state.passes = 0
      give_priority!(index)
    end

    def pass_priority!(index)
      emit Events::PriorityPassed.new(player: name(index))
      state.passes += 1
      if state.passes >= state.players.size && !state.stack.empty?
        ask!(nil)
        begin_resolution! # CR 117.4, 608
      elsif state.passes >= state.players.size
        # CR 117.4 / 500.2: all players passed with an empty stack -> the step ends.
        ask!(nil)
        state.step_state = "done"
      else
        give_priority!(state.opponent(index))
      end
    end

    def sorcery_timing?(index)
      state.active == index && Steps::MAIN_PHASE_STEPS.include?(state.step) && state.stack.empty? &&
        state.pending&.fetch("kind") == "priority"
    end

    # ---- objects & zones (CR 400) ------------------------------------------

    def create_object(card, owner, zone)
      id = "#{card}##{state.next_id}"
      state.next_id += 1
      state.objects[id] = GameObject.new(id: id, card: card, owner: owner, controller: owner, zone: zone,
                                         tapped: false, controlled_since: nil, kind: "card", counters: {},
                                         damage: 0, source: nil, ability: nil, targets: nil, loyalty_turn: nil)
    end

    # Moves an object to a zone as a new object (CR 400.7). Returns the new object.
    def move!(id, to, reason:, position: :top, controller: nil)
      old = object(id)
      state.zone_list(old.zone, old.owner).delete(id)
      state.objects.delete(id)
      fresh = create_object(old.card, old.owner, to)
      leave_combat!(id) if old.zone == :battlefield
      if to == :battlefield
        fresh.controller = controller || old.owner
        fresh.controlled_since = state.turn
        loyalty = definition(fresh).loyalty
        fresh.counters["loyalty"] = loyalty if loyalty # CR 306.5b
      elsif to == :stack
        fresh.controller = controller || old.owner
      end
      list = state.zone_list(to, old.owner)
      position == :bottom ? list.push(fresh.id) : list.unshift(fresh.id)
      emit Events::ZoneChanged.new(card: old.card, old_id: id, new_id: fresh.id, owner: name(old.owner),
                                   from: old.zone.to_s, to: to.to_s, reason: reason)
      fresh
    end

    def draw!(index)
      pl = player(index)
      if pl.library.empty?
        pl.drew_from_empty = true # CR 704.5b, checked as a state-based action
      else
        move!(pl.library.first, :hand, reason: "draw")
      end
    end

    def shuffle_library!(index)
      state.rng.shuffle!(player(index).library)
      emit Events::LibraryShuffled.new(player: name(index))
    end

    def tap!(object)
      object.tapped = true
      emit Events::Tapped.new(object: object.id)
    end

    def untap_all!(index)
      state.battlefield.each do |id|
        obj = object(id)
        next unless obj.controller == index && obj.tapped

        obj.tapped = false
        emit Events::Untapped.new(object: id)
      end
    end

    # CR 302.6: a creature's {T} abilities need it under continuous control since
    # the start of its controller's most recent turn.
    def summoning_sick_for_tap?(object)
      current = chars(object)
      return false if !current.creature? || current.keyword?(:haste)

      most_recent_turn = state.active == object.controller ? state.turn : state.turn - 1
      object.controlled_since.nil? || object.controlled_since >= most_recent_turn
    end

    # ---- mana (CR 106) ----------------------------------------------------------

    def add_mana!(index, produce, source)
      produce.each { |type| player(index).mana_pool[type] += 1 }
      emit Events::ManaAdded.new(player: name(index), mana: produce.map { "{#{it}}" }.join, source: source)
    end

    def empty_mana_pools!
      state.players.each do |pl|
        next if pl.mana_pool.values.all?(&:zero?)

        text = pl.mana_pool.flat_map { |type, n| ["{#{type}}"] * n }.join
        pl.mana_pool.transform_values! { 0 }
        emit Events::ManaEmptied.new(player: pl.name, mana: text)
      end
    end

    # ---- state-based actions & game end (CR 704, 104) ------------------------

    def check_state_based_actions!
      loop do
        check_player_state_based_actions!
        break if state.over? || !check_permanent_state_based_actions!
      end
    end

    def check_player_state_based_actions!
      state.players.each_with_index do |pl, i|
        next if pl.lost

        reason = if pl.life <= 0 then "life" # CR 704.5a
                 elsif pl.drew_from_empty then "empty_library" # CR 704.5b
                 elsif pl.poison >= 10 then "poison" # CR 704.5c
                 end
        pl.drew_from_empty = false
        lose!(i, reason) if reason
      end
      end_game_if_decided!
    end

    def concede!(index)
      lose!(index, "concede") # CR 104.3a
      end_game_if_decided!
    end

    def lose!(index, reason)
      player(index).lost = reason
      emit Events::PlayerLost.new(player: name(index), reason: reason)
    end

    # CR 104.2a: last player standing wins; CR 104.4a: all players losing at once is a draw.
    def end_game_if_decided!
      return if state.over?

      losers = state.players.select(&:lost)
      return if losers.empty?

      survivors = state.players.reject(&:lost)
      winner = survivors.size == 1 ? survivors.first.name : nil
      reason = losers.map(&:lost).uniq.join(",")
      state.result = { "winner" => winner, "reason" => reason }
      ask!(nil)
      state.frames.clear
      emit Events::GameEnded.new(winner: winner, reason: reason)
    end

    # ---- decisions --------------------------------------------------------------

    def options
      return [] unless state.pending

      @options_memo = {}
      Decisions.fetch(state.pending["kind"]).options(self, state.pending)
    ensure
      @options_memo = nil
    end

    def submit!(option)
      Decisions.fetch(state.pending["kind"]).submit(self, state.pending, option)
      advance!
    end
  end
end
