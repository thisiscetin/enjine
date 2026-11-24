# frozen_string_literal: true

# Invented cards for the effects, zones and loops shapes: "repeat this process" (CR 608.2c), exiling until a
# total mana value or a card (CR 406.1), targeting a card exiled with the source (CR 607.2a), "if it was
# attacking" (CR 608.2h), the Nth counter (CR 122.6) and changing a target (CR 115.7a).
RSpec.describe "Effects, zones and loops gaps (invented cards)" do
  # Alice's precombat main phase of turn 3 (or `active`'s), with nine mana of each type in each player's pool.
  def board(alice: {}, bob: {}, active: "alice")
    build_game do
      turn 3, active: active, step: :precombat_main
      { "alice" => alice, "bob" => bob }.each do |name, zones|
        player(name, mana_pool: Enjine::Mana::TYPES.to_h { [it, 9] }) do
          %i[hand graveyard exile].each { |zone| Array(zones[zone]).each { send(zone, it) } }
          Array(zones[:battlefield]).each { |card, opts| battlefield card, **(opts || {}) }
          library(*zones.fetch(:library, ["Forest"] * 10))
        end
      end
    end
  end

  def engine(game) = game.instance_variable_get(:@engine)
  def player_of(game, name) = game.state.players[game.names.index(name)]
  def names(game, name, zone) = player_of(game, name).public_send(zone).map { game.state.object(it).card }
  def on_battlefield(game, name) = game.state.battlefield.map { game.state.object(it) }.select { it.controller == game.names.index(name) }
  def id(game, card, zone: :battlefield, player: "alice") = obj_id(game, card, zone: zone, player: player)
  def exiled(game, card) = game.state.exile.find { game.state.object(it).card == Enjine::CardDefinition.slug(card) }

  # Answers decisions until the stack is empty at a priority decision (or `stop` holds): the next `answers`
  # entry matching a legal option (a partial hash), else a mana payment, else a pass, else "done".
  def drive(game, answers, stop: ->(g) { g.state.stack.empty? })
    500.times do
      options = game.legal_options
      wanted = answers.find { |a| options.any? { |o| a.all? { |k, v| o[k] == v } } }
      answer = wanted && options.find { |o| wanted.all? { |k, v| o[k] == v } }
      if answer then answers.delete_at(answers.index(wanted))
      elsif game.pending_decision.kind == "pay_cost"
        answer = options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" }
      elsif game.pending_decision.kind == "priority"
        return game if answers.empty? && stop.call(game)

        answer = { type: "pass" }
      elsif options.include?({ type: "done" }) then answer = { type: "done" }
      else raise "no answer for #{game.pending_decision.kind} #{options}"
      end
      game.submit(answer)
    end
    raise "drive did not settle: answers left #{answers}"
  end

  def cast(game, card, *answers, player: "alice", stop: ->(g) { g.state.stack.empty? })
    game.submit(type: "cast", object: id(game, card, zone: :hand, player: player))
    drive(game, answers, stop: stop)
  end

  describe "Tidal Recursion: repeat this process (CR 608.2c)" do
    it "mills and returns lands tapped until it mills a nonland card" do
      game = board(alice: { hand: ["Tidal Recursion"], library: ["Forest", "Island", "Grizzly Bears", "Forest"] })
      cast(game, "Tidal Recursion")
      lands = on_battlefield(game, "alice").select { %w[forest island].include?(it.card) }
      expect(lands.map { [it.card, it.tapped] }).to contain_exactly(["forest", true], ["island", true])
      expect(names(game, "alice", :graveyard)).to contain_exactly("grizzly_bears", "tidal_recursion")
      expect(names(game, "alice", :library)).to eq(["forest"])
    end
  end

  describe "Hoard Glimpse: exile until a total mana value (CR 406.1)" do
    it "exiles until the mana values total 3, then casts any of them free" do
      game = board(alice: { hand: ["Hoard Glimpse"], library: ["Grizzly Bears", "Forest", "Raging Goblin", "Hill Giant"] })
      cast(game, "Hoard Glimpse", { type: "cast" }, { type: "cast" })
      expect(on_battlefield(game, "alice").map(&:card)).to include("grizzly_bears", "raging_goblin")
      expect(game.state.exile.map { game.state.object(it).card }).to eq(["forest"])
      expect(names(game, "alice", :library)).to eq(["hill_giant"])
    end
  end

  describe "Unearthed Secrets: each opponent exiles until a nonland card" do
    it "stops at the first nonland card, then draws" do
      game = board(alice: { hand: ["Unearthed Secrets"] }, bob: { library: ["Island", "Forest", "Hill Giant", "Forest"] })
      cast(game, "Unearthed Secrets")
      expect(game.state.exile.map { game.state.object(it).card }).to contain_exactly("island", "forest", "hill_giant")
      expect(names(game, "bob", :library)).to eq(["forest"])
      expect(names(game, "alice", :hand).size).to eq(1)
    end
  end

  describe "Recall the Charge: if it was attacking (CR 608.2h)" do
    it "draws only when the returned creature was attacking" do
      game = board(alice: { hand: ["Recall the Charge"] }, bob: { battlefield: [["Grizzly Bears"]] })
      cast(game, "Recall the Charge", { target: id(game, "Grizzly Bears", player: "bob") })
      expect([names(game, "bob", :hand), names(game, "alice", :hand)]).to eq([["grizzly_bears"], []])

      game = board(alice: { hand: ["Recall the Charge"],
                            battlefield: [["Grizzly Bears", { controlled_since: 1 }], ["Island"], ["Island"]] })
      bears = id(game, "Grizzly Bears")
      drive(game, [{ type: "attack", object: bears }], stop: ->(g) { g.step == :declare_attackers && g.state.stack.empty? })
      cast(game, "Recall the Charge", { target: bears })
      expect(names(game, "alice", :hand)).to contain_exactly("grizzly_bears", "forest")
    end
  end

  describe "Vault of Lost Souls: a card exiled with this permanent (CR 607.2a)" do
    it "exiles an opponent's dying creature and later puts only that card onto the battlefield under your control" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Vault of Lost Souls"]] },
                   bob: { battlefield: [["Grizzly Bears"]], exile: ["Hill Giant"] })
      cast(game, "Lightning Bolt", { target: id(game, "Grizzly Bears", player: "bob") })
      exiled = exiled(game, "Grizzly Bears")
      vault = id(game, "Vault of Lost Souls")
      game.submit(game.legal_options.find { it[:type] == "activate" && it[:object] == vault })
      expect(game.legal_options.filter_map { it[:target] }).to eq([exiled]) # not Hill Giant: not exiled with it
      drive(game, [{ target: exiled }])
      bears = on_battlefield(game, "alice").find { it.card == "grizzly_bears" }
      expect(bears.tapped).to be(true)
    end
  end

  describe "Siege Plan: the third plan counter (CR 122.6)" do
    it "the counter that makes three sacrifices it for 4 damage; the second doesn't" do
      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Siege Plan", { counters: { "plan" => 1 } }]] })
      cast(game, "Lightning Bolt", { target: "player:bob" })
      expect(game.state.object(id(game, "Siege Plan")).counters).to eq("plan" => 2)

      game = board(alice: { hand: ["Lightning Bolt"], battlefield: [["Siege Plan", { counters: { "plan" => 2 } }]] })
      cast(game, "Lightning Bolt", { target: "player:bob" }, { target: "player:bob" })
      expect(names(game, "alice", :graveyard)).to include("siege_plan")
      expect(player_of(game, "bob").life).to eq(13)
    end
  end

  describe "Bending Ricochet: change the target (CR 115.7a)" do
    it "moves an opponent's Lightning Bolt to another legal target" do
      game = board(alice: { hand: ["Bending Ricochet"], battlefield: [["Grizzly Bears"]] }, bob: { hand: ["Lightning Bolt"] },
                   active: "bob")
      cast(game, "Lightning Bolt", { target: "player:alice" }, player: "bob", stop: ->(g) { g.state.priority.zero? })
      bolt = game.state.stack.first
      bears = id(game, "Grizzly Bears")
      cast(game, "Bending Ricochet", { target: bolt }, stop: ->(g) { g.state.stack.size == 2 })
      drive(game, [{ target: bears }], stop: ->(g) { g.state.stack.size == 1 })
      expect(game.state.object(bolt).targets).to eq([bears])
    end
  end
end
