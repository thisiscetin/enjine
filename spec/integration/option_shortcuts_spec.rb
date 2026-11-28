# frozen_string_literal: true

# The quick nos and per-decision memos legal options use (Engine#options) must never change the options: each is
# checked here against the case it would get wrong if it were too eager. script/determinism_digest.rb checks the
# same over hundreds of whole games.
RSpec.describe "Legal option shortcuts" do
  def engine(game) = game.instance_variable_get(:@engine)
  def cast_ids(game) = game.legal_options.select { it[:type] == "cast" }.map { it[:object] }

  def main_phase(catalog = core_catalog, &)
    build_game(catalog) do
      turn 3, active: "alice", step: :precombat_main
      player("alice") do
        instance_eval(&)
        library "Mountain", count: 5
      end
      player("bob") { library "Mountain", count: 5 }
    end
  end

  describe "the mana pre-check (CR 601.2f-h)" do
    it "offers no spell whose colored symbols the player's mana can't reach, and offers it once it can" do
      tapped = main_phase do
        hand "Lightning Bolt"
        battlefield "Mountain", tapped: true
      end
      expect(cast_ids(tapped)).to be_empty

      open = main_phase do
        hand "Lightning Bolt"
        battlefield "Mountain"
      end
      expect(cast_ids(open)).to eq([obj_id(open, "Lightning Bolt", zone: :hand, player: "alice")])
    end

    it "counts mana in the pool" do
      game = main_phase { hand "Lightning Bolt" }
      game.state.players[0].mana_pool[:R] = 1
      expect(cast_ids(game.fork)).not_to be_empty
    end

    it "counts creatures a convoke spell could tap (CR 702.51a)" do
      game = main_phase do
        hand "Crowd Uprising"
        battlefield "Savannah Lions", count: 4 # nothing taps for mana: only convoke pays, {W} too
      end
      expect(cast_ids(game)).to eq([obj_id(game, "Crowd Uprising", zone: :hand, player: "alice")])
    end

    it "gives a card that is a copy the full look" do
      game = main_phase do
        hand "Lightning Bolt"
        battlefield "Mountain", tapped: true
      end
      bolt = engine(game).object(obj_id(game, "Lightning Bolt", zone: :hand, player: "alice"))
      bolt.memory["copy_except"] = { "power" => 1 }
      eng = engine(game)
      eng.instance_variable_set(:@options_memo, {})
      expect(eng.mana_out_of_reach?(0, bolt)).to be(false)
      eng.instance_variable_set(:@options_memo, nil)
      expect(eng.mana_out_of_reach?(0, bolt)).to be(false) # only while options are computed
    end

    it "never bounds the mana below what the player could make, in random games" do
      setup = Enjine::Setup.new(*%w[p1 p2].each_with_index.map do |name, i|
        Enjine::Player.new(name: name, deck: Enjine::Fuzz.random_deck(CardFixtures.cards, rng: Enjine::Rng.from_seed(i + 5)))
      end)
      game = setup.new_game(seed: 5)
      agent = Enjine::Agents::Random.new(seed: 5)
      eng = engine(game)
      checked = 0
      600.times do
        break if game.over?

        decision = game.pending_decision
        if decision.kind == "priority"
          index = game.names.index(decision.player)
          eng.instance_variable_set(:@options_memo, {})
          ids = game.state.players[index].hand + [nil]
          ids.each { expect(eng.mana_unit_bound(index)).to be >= eng.mana_units(index, nil, it && { "spell" => it }).size }
          eng.instance_variable_set(:@options_memo, nil)
          checked += 1
        end
        game.submit(agent.choose(decision))
      end
      expect(checked).to be_positive
    end
  end

  describe "off-board quick nos (CR 113.6b)" do
    let(:grant) do
      lambda do |game, id, card, ref|
        game.state.effects << { "kind" => "card_ability", "timestamp" => 99, "controller" => 0, "affected" => [id],
                                "duration" => "permanent", "card" => card, "ability" => ref }
        game.fork # a fresh game recomputes the options
      end
    end

    it "still sees an alternative cost an effect grants a card in hand" do
      game = main_phase do
        hand "Grizzly Bears"
        battlefield "Mountain"
      end
      bears = obj_id(game, "Grizzly Bears", zone: :hand, player: "alice")
      expect(game.legal_options.select { it[:object] == bears && it[:via] }).to be_empty
      granted = grant.call(game, bears, "flicker_wisp", "printed:1") # evoke {R}
      expect(granted.legal_options.select { it[:object] == bears && it[:via] }).not_to be_empty
    end

    it "still sees a special action an effect grants a card in hand (CR 116.2h)" do
      game = main_phase do
        hand "Grizzly Bears"
        battlefield "Mountain", count: 2
      end
      bears = obj_id(game, "Grizzly Bears", zone: :hand, player: "alice")
      expect(option_types(game)).not_to include("special_action")
      granted = grant.call(game, bears, "portent_spark", "printed:1") # foretell
      expect(granted.legal_options).to include(a_hash_including(type: "special_action", object: bears))
    end
  end

  describe "exiled cards of the opponent (CR 108.3, 611.2)" do
    it "are playable only by a permission naming them" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Mountain"
          library "Mountain", count: 5
        end
        player("bob") do
          exile "Lightning Bolt"
          library "Mountain", count: 5
        end
      end
      bolt = game.state.exile.first
      expect(cast_ids(game)).to be_empty
      game.state.effects << { "kind" => "permission", "timestamp" => 99, "controller" => 0, "affected" => [bolt],
                              "duration" => "end_of_turn", "turn" => 3, "play" => "cast" }
      expect(cast_ids(game.fork)).to eq([bolt])
    end
  end

  describe "views" do
    it "show the same pending options whether or not the caller passes them" do
      game = main_phase do
        hand "Lightning Bolt"
        battlefield "Mountain"
      end
      eng = engine(game)
      expect(game.view_for("alice")).to eq(Enjine::View.build(eng, "alice"))
      expect(game.view_for("observer")).to eq(Enjine::View.build(eng, :observer))
      expect(game.view_for("alice")["pending"]["options"]).to include({ "type" => "cast", "object" => cast_ids(game).first })
    end
  end

  describe "Snapshot.deep_copy" do
    it "copies plain data like a Marshal round trip, with fresh unfrozen strings" do
      data = { "a" => [1, 2.5, :sym, nil, true, false, { "b" => "text".dup.freeze }], :c => "x" }
      copy = Enjine::Snapshot.deep_copy(data)
      expect(copy).to eq(Marshal.load(Marshal.dump(data)))
      expect(copy["a"][6]["b"]).not_to be_frozen
      expect(copy["a"][6]["b"]).not_to equal(data["a"][6]["b"])
    end

    it "takes the Marshal round trip for anything else" do
      counted = Hash.new(0).merge("x" => 1)
      copy = Enjine::Snapshot.deep_copy([counted, Set[1, 2]])
      expect(copy[0]["missing"]).to eq(0) # the default survives
      expect(copy[1]).to eq(Set[1, 2])
      expect(copy[1]).not_to equal(Set[1, 2])
    end
  end
end
