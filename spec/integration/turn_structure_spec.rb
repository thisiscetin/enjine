# frozen_string_literal: true

RSpec.describe "Turn structure: phasing, optional untap, land plays, first time each turn (CR 305.2, 502, 702.26)" do
  def pay_all(game)
    while game.pending_decision&.kind == "pay_cost"
      options = game.legal_options
      game.submit(options.find { it[:type] == "pay_mana" } || options.find { it[:type] == "activate_mana" })
    end
  end

  def cast(game, card, *targets, player: "alice")
    game.submit(type: "cast", object: obj_id(game, card, zone: :hand, player: player))
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def activate(game, id, *targets)
    game.submit(type: "activate", object: id, ability: "printed:#{game.catalog.fetch(game.state.object(id).card).abilities.index do
      it.kind == :activated
    end}")
    targets.each { game.submit(type: "target", target: it) }
    pay_all(game)
  end

  def attack(game, id)
    game.submit(type: "attack", object: id, target: "player:bob")
    game.submit(type: "done") if game.pending_decision.kind == "declare_attackers"
  end

  def resolve(game)
    game.submit(type: "pass") until game.state.stack.empty? || game.over? || game.pending_decision.kind != "priority"
  end

  def token_id(game, name) = game.state.battlefield.find { game.catalog.fetch(game.state.object(it).card).name == name }
  def cards(game, ids) = ids.map { game.state.object(it).card }
  def life(game, who) = game.state.players[game.names.index(who)].life

  # Passes (answering every other decision with its first option) until a decision of `kind` comes up.
  def advance_to_decision(game, kind, limit: 300)
    limit.times do
      return game if game.pending_decision&.kind == kind

      types = option_types(game)
      game.submit({ type: if types.include?("pass")
                            "pass"
                          else
                            (types.include?("done") ? "done" : types.first)
                          end })
    end
    raise "no #{kind} decision"
  end

  describe "phasing (CR 702.26)" do
    def phasing_game
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 3, B: 1 }) do
          hand "Temporal Fold", "Grim Accounting"
          battlefield "Grizzly Bears", "Flickerwing Drake", "Charged Relay"
          library "Island", count: 10
        end
        player("bob", mana_pool: { R: 1 }) do
          hand "Lightning Bolt"
          battlefield "Hill Giant"
          library "Island", count: 10
        end
      end
    end

    it "phase_out keeps the objects, emits no zone changes, and they can't be targeted (702.26b, 702.26d)" do
      game = phasing_game
      bears = obj_id(game, "Grizzly Bears")
      giant = obj_id(game, "Hill Giant")
      relay = obj_id(game, "Charged Relay")
      cast(game, "Temporal Fold")
      seen = []
      game.subscribe { seen << it }
      resolve(game)
      expect(game.state.phased_out).to include(bears, giant, relay)
      expect(game.state.object(bears).zone).to eq(:phased_out)
      expect(game.state.object(bears).phased_out).to eq("by" => 0, "indirectly" => false)
      expect(game.state.battlefield).to eq([token_id(game, "Stasis Warden")])
      expect(seen.grep(Enjine::Events::ZoneChanged).size).to eq(2) # the spell to the graveyard, the token
      expect(seen.grep(Enjine::Events::PhasedOut).size).to eq(4)
      game.submit(type: "pass") until game.pending_decision.player == "bob"
      game.submit(type: "cast", object: obj_id(game, "Lightning Bolt", zone: :hand, player: "bob"))
      expect(game.legal_options.map { it[:target] }).not_to include(bears, giant)
      view = game.view_for(:observer)
      expect(view["phased_out"].map { it["id"] }).to include(bears)
      expect(view["phased_out"].first["phased_out"]).to be(true)
    end

    it "a permanent with 'permanents can't phase in' keeps them out; without it they phase in in the untap step (502.1)" do
      game = phasing_game
      bears = obj_id(game, "Grizzly Bears")
      giant = obj_id(game, "Hill Giant")
      cast(game, "Temporal Fold")
      resolve(game)
      skip_to(game, :upkeep, turn: 4)
      expect(game.state.phased_out).to include(giant)
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)

      game.state.battlefield.delete(warden = token_id(game, "Stasis Warden"))
      game.state.objects.delete(warden)
      game.state.players[0].graveyard # the warden is gone: nothing stops phasing in now
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.battlefield).to include(bears)
      expect(game.state.phased_out).to include(giant) # bob's phase in on bob's turn
      skip_to(game, :upkeep, turn: 6)
      expect(game.state.phased_out).to be_empty
      expect(game.state.battlefield).to include(giant)
    end

    it "a creature with phasing phases out and in on alternate untap steps of its controller (702.26a)" do
      game = phasing_game
      drake = obj_id(game, "Flickerwing Drake")
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.phased_out).to eq([drake])
      skip_to(game, :upkeep, turn: 7)
      expect(game.state.phased_out).to be_empty
      expect(game.state.battlefield).to include(drake)
    end

    it "Auras phase out indirectly with their creature and phase back in attached (702.26g, 702.26i)" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { U: 3, R: 1 }) do
          hand "Temporal Fold", "Emberbond Charm"
          battlefield "Grizzly Bears"
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
      bears = obj_id(game, "Grizzly Bears")
      cast(game, "Emberbond Charm", bears)
      resolve(game)
      charm = obj_id(game, "Emberbond Charm")
      expect(game.state.object(charm).attached_to).to eq(bears)
      cast(game, "Temporal Fold")
      resolve(game)
      expect(game.state.object(charm).phased_out).to eq("by" => 0, "indirectly" => true)
      warden = token_id(game, "Stasis Warden")
      game.state.battlefield.delete(warden)
      game.state.objects.delete(warden)
      skip_to(game, :upkeep, turn: 5)
      expect(game.state.battlefield).to include(bears, charm)
      expect(game.state.object(charm).attached_to).to eq(bears)
      expect(game.state.object(charm).phased_out).to be_nil
    end

    it "a phased-out attacker is removed from combat (506.4)" do
      game = phasing_game
      bears = obj_id(game, "Grizzly Bears")
      advance_to_decision(game, "declare_attackers")
      attack(game, bears)
      engine = Enjine::Engine.new(game.catalog, game.state) { nil }
      engine.phase_out!([bears])
      expect(game.state.attackers).not_to have_key(bears)
    end

    it "an edict on tokens gains life only if a token was sacrificed" do
      game = phasing_game
      cast(game, "Temporal Fold")
      resolve(game)
      cast(game, "Grim Accounting")
      resolve(game)
      expect(life(game, "alice")).to eq(25)
      expect(game.state.battlefield).to be_empty

      other = phasing_game
      cast(other, "Grim Accounting")
      resolve(other)
      expect(life(other, "alice")).to eq(20)
    end

    it "snapshots reject malformed phasing data" do
      data = JSON.parse(phasing_game.export)
      data["state"]["objects"][0]["phased_out"] = { "by" => 0, "indirectly" => false }
      expect { Enjine::Game.import(data, catalog: core_catalog) }.to raise_error(Enjine::Error, /only phased-out permanents/)
      data = JSON.parse(phasing_game.export)
      obj = data["state"]["objects"].find { it["zone"] == "battlefield" }
      data["state"]["battlefield"].delete(obj["id"])
      data["state"]["phased_out"] = [obj["id"]]
      obj["zone"] = "phased_out"
      expect { Enjine::Game.import(data, catalog: core_catalog) }.to raise_error(Enjine::Error, /phased_out: must be/)
      obj["phased_out"] = { "by" => 1, "indirectly" => false }
      expect(Enjine::Game.import(data, catalog: core_catalog).state.phased_out).to eq([obj["id"]])
    end
  end

  describe "may choose not to untap (CR 502.3) and extra triggers while tapped (603.2d, 611.2b)" do
    def sentinel_game
      build_game do
        turn 2, active: "bob", step: :end
        player("alice") do
          battlefield "Drowsy Sentinel", "Forest", tapped: true
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
    end

    it "asks the active player about each such tapped permanent and untaps the rest" do
      game = sentinel_game
      advance_to_decision(game, "untap_choice")
      sentinel = obj_id(game, "Drowsy Sentinel")
      expect(game.pending_decision.player).to eq("alice")
      expect(game.legal_options).to eq([{ type: "untap", object: sentinel }, { type: "keep_tapped", object: sentinel }])
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)
      game.submit(type: "keep_tapped", object: sentinel)
      expect(game.state.object(sentinel).tapped).to be(true)
      expect(game.state.object(obj_id(game, "Forest")).tapped).to be(false)
      expect(game.step).to eq(:upkeep)
    end

    it "untaps it when the player chooses to" do
      game = sentinel_game
      advance_to_decision(game, "untap_choice")
      sentinel = obj_id(game, "Drowsy Sentinel")
      game.submit(type: "untap", object: sentinel)
      expect(game.state.object(sentinel).tapped).to be(false)
    end

    it "the tapped source makes the target's triggered abilities trigger twice until it untaps" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Drowsy Sentinel", "Ferry Pilot"
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
      sentinel = obj_id(game, "Drowsy Sentinel")
      pilot = obj_id(game, "Ferry Pilot")
      activate(game, sentinel, pilot)
      resolve(game)
      expect(game.state.effects.map { it["kind"] }).to eq(["additional_triggers"])
      advance_to_decision(game, "declare_attackers")
      attack(game, pilot)
      expect(game.pending_decision.kind).to eq("order_triggers") # two instances of the same trigger
      game.submit(game.legal_options.first) while game.pending_decision.kind == "order_triggers"
      expect(game.state.stack.size).to eq(2)
      Enjine::Engine.new(game.catalog, game.state) { nil }.untap!(game.state.object(sentinel))
      expect(game.state.effects).to be_empty
    end

    it "does nothing if the source is no longer tapped as it resolves (611.2b)" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Drowsy Sentinel", "Ferry Pilot"
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
      sentinel = obj_id(game, "Drowsy Sentinel")
      activate(game, sentinel, obj_id(game, "Ferry Pilot"))
      game.state.object(sentinel).tapped = false
      resolve(game)
      expect(game.state.effects).to be_empty
    end
  end

  describe "additional land plays (CR 305.2)" do
    def lands_game(*permanents, lands: 3)
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { R: 1 }) do
          hand "Forest", count: lands
          battlefield(*permanents) unless permanents.empty?
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
    end

    def play_land(game) = game.submit(game.legal_options.find { it[:type] == "play_land" })
    def can_play_land?(game) = option_types(game).include?("play_land")

    it "is one land per turn plus one for each additional_land_plays ability" do
      game = lands_game
      play_land(game)
      expect(can_play_land?(game)).to be(false)

      game = lands_game("Wandering Surveyor")
      2.times { play_land(game) }
      expect(can_play_land?(game)).to be(false)
      expect(game.state.players[0].lands_played).to eq(2)
    end

    it "become: types, base power/toughness and abilities for as long as it stays (layers 4, 6, 7b)" do
      game = lands_game("Shifting Cadet")
      cadet = obj_id(game, "Shifting Cadet")
      expect(option_types(game)).to include("activate")
      activate(game, cadet)
      resolve(game)
      view = view_of(game, cadet)
      expect(view).to include("power" => 3, "toughness" => 4)
      chars = Enjine::Engine.new(game.catalog, game.state) { nil }.chars(cadet)
      expect(chars.subtypes).to contain_exactly(:goblin, :scout)
      2.times { play_land(game) }
      expect(can_play_land?(game)).to be(false)
      expect(option_types(game)).not_to include("activate") # no longer a Rogue
      copy = Enjine::Game.import(game.export, catalog: game.catalog)
      expect(copy.state.to_h).to eq(game.state.to_h)
      skip_to(game, :upkeep, turn: 5)
      expect(view_of(game, cadet)).to include("power" => 3, "toughness" => 4)
      advance_to_decision(game, "declare_attackers")
      before = life(game, "alice")
      attack(game, cadet)
      resolve(game)
      expect(life(game, "alice")).to eq(before + 1) # the gained becomes_tapped trigger
    end

    it "a land put onto the battlefield by an effect isn't a land play (305.2a); return_choice later" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          hand "Forest", count: 2
          battlefield "Ferry Pilot", "Mountain"
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
      game.submit(game.legal_options.find { it[:type] == "play_land" })
      advance_to_decision(game, "declare_attackers")
      attack(game, obj_id(game, "Ferry Pilot"))
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      forest = ids_in(game, "alice", :hand).first
      expect(game.legal_options).to include({ type: "choose", object: forest }, { type: "done" })
      game.submit(type: "choose", object: forest)
      expect(cards(game, game.state.battlefield).count("forest")).to eq(2)
      expect(game.state.players[0].lands_played).to eq(1)
      expect(ids_in(game, "alice", :hand)).to be_empty
      advance_to_decision(game, "effect_choice") until game.step == :end && game.pending_decision.kind == "effect_choice"
      expect(game.legal_options.map { it[:type] }.uniq).to eq(["return"])
      expect(game.legal_options.size).to eq(3) # any land alice controls: chosen, not targeted
      mountain = obj_id(game, "Mountain")
      game.submit(type: "return", object: mountain)
      expect(cards(game, ids_in(game, "alice", :hand))).to eq(["mountain"])
    end
  end

  describe "for the first time each turn (counters_placed first_time_this_turn)" do
    it "triggers on the first placement of that counter this turn only" do
      game = build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice", mana_pool: { C: 3 }) do
          battlefield "Charged Relay"
          library "Island", count: 10
        end
        player("bob") { library "Island", count: 10 }
      end
      relay = obj_id(game, "Charged Relay")
      hand = -> { ids_in(game, "alice", :hand).size }
      activate(game, relay)
      resolve(game)
      expect(hand.call).to eq(1)
      activate(game, relay)
      resolve(game)
      expect(hand.call).to eq(1)
      expect(game.state.object(relay).counters["charge"]).to eq(2)
    end
  end

  describe "\"that player\" for a beginning-of-step trigger is the active player" do
    let(:banner) do
      { "name" => "Armistice Pennant", "mana_cost" => "{1}{W}", "types" => ["enchantment"],
        "abilities" => [{ "triggered" => {
          "when" => { "step_begins" => { "step" => "beginning_of_combat", "whose" => "each" } },
          "effects" => [{ "may" => { "chooser" => { "triggering" => "player" },
                                     "effects" => [{ "draw" => { "amount" => 1, "to" => { "triggering" => "player" } } }],
                                     "then" => [{ "player_rule" => { "rule" => "cant_attack", "to" => { "triggering" => "player" } } },
                                                { "add_counters" => { "counter" => "peace", "amount" => 1, "to" => "self" } }] } }]
        } }] }
    end

    it "lets the active opponent draw and then keeps them from attacking" do
      game = build_game(catalog_with(banner)) do
        turn 4, active: "bob", step: :precombat_main
        player("alice") do
          battlefield "Armistice Pennant"
          library "Island", count: 10
        end
        player("bob") do
          battlefield "Grizzly Bears"
          library "Island", count: 10
        end
      end
      game.submit(type: "pass") until game.pending_decision.kind == "effect_choice"
      expect(game.pending_decision.player).to eq("bob")
      game.submit(type: "yes")
      expect(ids_in(game, "bob", :hand).size).to eq(1)
      expect(game.state.object(obj_id(game, "Armistice Pennant")).counters["peace"]).to eq(1)
      game.submit(type: "pass") until game.pending_decision.kind != "priority" || game.step != :beginning_of_combat
      expect(game.pending_decision.kind).not_to eq("declare_attackers")
    end
  end
end
