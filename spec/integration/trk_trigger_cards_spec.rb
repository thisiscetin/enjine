# frozen_string_literal: true

# Plays converted Star Trek cards from lib/enjine/sets/trk.json (structured data only).
RSpec.describe "Converted trk cards with trigger mechanics" do
  let(:catalog) { catalog_with(*Enjine::Sets.load("trk").cards) }

  def slug(card) = Enjine::CardDefinition.slug(card)
  def life(game, index) = game.state.players[index].life
  def hand_id(game, player, card) = ids_in(game, player, :hand).find { game.state.object(it).card == slug(card) }

  def pay_all(game)
    game.submit(game.legal_options.find { it[:type] == "pay_mana" }) while game.pending_decision.kind == "pay_cost"
  end

  def cast(game, card, player: "alice", targets: [])
    game.submit(type: "cast", object: hand_id(game, player, card))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def advance_to(game, kind, limit: 30)
    limit.times do
      return if game.pending_decision.kind == kind

      game.submit(type: "pass")
    end
    raise "no #{kind} decision"
  end

  def settle(game, limit: 30)
    limit.times do
      break if game.pending_decision.kind == "priority" && game.state.stack.empty?

      game.pending_decision.kind == "priority" ? game.submit(type: "pass") : game.submit(game.legal_options.first)
    end
  end

  def board(&)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      instance_eval(&)
    end
  end

  it "Federation Outpost: enters untapped with two other lands, and its modal trigger gains life" do
    game = board do
      player("alice") do
        hand "Federation Outpost"
        battlefield "Plains", count: 2
      end
      player("bob")
    end
    game.submit(type: "play_land", object: hand_id(game, "alice", "Federation Outpost"))
    expect(game.pending_decision.kind).to eq("choose_mode")
    game.submit(type: "mode", mode: 0)
    settle(game)
    expect(life(game, 0)).to eq(22)
    expect(game.state.object(obj_id(game, "Federation Outpost")).tapped).to be(false)
  end

  it "Dr. Beverly Crusher: her life-gain trigger triggers twice" do
    game = board do
      player("alice", mana_pool: { W: 2 }) do
        battlefield "Dr. Beverly Crusher"
        hand "Revitalize"
        library "Plains", count: 3
      end
      player("bob")
    end
    cast(game, "Revitalize")
    settle(game)
    expect(game.state.object(obj_id(game, "Dr. Beverly Crusher")).counters).to eq("+1/+1" => 2)
  end

  it "Kai Winn: an opponent casting the named spell loses 3 life" do
    game = board do
      player("alice", mana_pool: { B: 2 }) { hand "Kai Winn, Faithless Leader" }
      player("bob", mana_pool: { R: 1 }) { hand "Lightning Bolt" }
    end
    cast(game, "Kai Winn, Faithless Leader")
    advance_to(game, "enter_choice")
    game.submit(type: "name", name: "Lightning Bolt")
    game.submit(type: "pass")
    cast(game, "Lightning Bolt", player: "bob", targets: ["player:alice"])
    settle(game)
    expect(life(game, 1)).to eq(17)
  end

  it "A Good Day to Die: drawing when the pumped creature dies that turn" do
    game = board do
      player("alice", mana_pool: { B: 1, R: 1 }) do
        battlefield "Grizzly Bears"
        hand "A Good Day to Die", "Lightning Bolt"
        library "Swamp", count: 3
      end
      player("bob")
    end
    bears = obj_id(game, "Grizzly Bears")
    cast(game, "A Good Day to Die", targets: [bears])
    settle(game)
    cast(game, "Lightning Bolt", targets: [bears])
    settle(game)
    expect(ids_in(game, "alice", :hand).size).to eq(1)
  end

  it "Tell Me What You See: the targeted opponent decides; declining costs them 4 life and you surveil" do
    game = board do
      player("alice", mana_pool: { B: 2 }) do
        hand "Tell Me What You See"
        library "Swamp", count: 3
      end
      player("bob")
    end
    cast(game, "Tell Me What You See")
    advance_to(game, "choose_target")
    game.submit(type: "target", target: "player:bob")
    advance_to(game, "effect_choice")
    expect(game.pending_decision.player).to eq("bob")
    game.submit(type: "no")
    expect(life(game, 1)).to eq(16)
    expect(game.pending_decision.player).to eq("alice") # surveil
  end

  it "U.S.S. Reliant: returns a creature card with mana value 4 or less with a finality counter as it enters" do
    game = board do
      player("alice", mana_pool: { B: 4 }) do
        hand "U.S.S. Reliant, From Hell's Heart"
        graveyard "Hill Giant", "Craw Wurm"
      end
      player("bob")
    end
    cast(game, "U.S.S. Reliant, From Hell's Heart")
    advance_to(game, "choose_target")
    expect(game.legal_options.map { game.state.object(it[:target]).card }).to eq(["hill_giant"])
    game.submit(game.legal_options.first)
    settle(game)
    expect(game.state.object(obj_id(game, "Hill Giant")).counters).to eq("finality" => 1)
  end
end
