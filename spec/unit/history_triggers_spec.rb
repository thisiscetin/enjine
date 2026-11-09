# frozen_string_literal: true

# Invented test cards only.
RSpec.describe "Zone-change triggers and turn-history values" do
  def build(category, data, path = "x", **context)
    errors = []
    built = Enjine::Mechanics.build_entry(category, data, errors, path, **context)
    [built, errors]
  end

  def errors_of(category, data) = build(category, data)[1]
  def trigger(data) = build(:trigger, data)[0]

  describe "validation (path-addressed errors)" do
    it "rejects bad trigger parameters" do
      expect(errors_of(:trigger, { "leaves_battlefield" => { "to" => "stack" } }))
        .to eq(["x.leaves_battlefield.to: must be one of graveyard, exile, hand, library"])
      expect(errors_of(:trigger, { "sacrifices" => { "batched" => 1 } })).to eq(["x.sacrifices.batched: must be true or false"])
      players = "must be one of you, opponent, any"
      zones = "must be a list of battlefield, graveyard, hand, library, stack, exile"
      expect(errors_of(:trigger, { "discards" => { "controller" => "me", "card" => { "wizard" => {} } } }))
        .to contain_exactly("x.discards.controller: #{players}", a_string_matching(/x.discards.card: unknown filter/))
      expect(errors_of(:trigger, { "cycles" => { "color" => "blue" } })).to eq(['x.cycles: unknown parameter "color"'])
      expect(errors_of(:trigger, { "scries" => { "controller" => "all" } })).to eq(["x.scries.controller: #{players}"])
      expect(errors_of(:trigger, { "becomes_untapped" => { "subject" => "everyone" } }))
        .to include(a_string_matching(/x.becomes_untapped.subject: must be "self"/))
      expect(errors_of(:trigger, { "put_into" => { "zone" => "hand" } })).to eq(["x.put_into.zone: must be one of graveyard, exile"])
      expect(errors_of(:trigger, { "put_into" => { "zone" => "exile", "from" => ["nowhere"] } })).to eq(["x.put_into.from: #{zones}"])
      expect(errors_of(:trigger, { "put_into" => { "zone" => "exile", "from" => [] } })).to eq(["x.put_into.from: #{zones}"])
    end

    it "rejects bad history amounts and accepts the raid flag" do
      errors = []
      Enjine::Mechanics::Amount.build({ "left_this_turn" => { "controller" => "them", "colour" => "red" } }, errors, "a", targets_count: 0)
      expect(errors).to eq(['a.left_this_turn: unknown parameter "colour"',
                            "a.left_this_turn.controller: must be one of you, opponent, any"])
      errors = []
      Enjine::Mechanics::Amount.build({ "exiled_this_turn" => "you" }, errors, "a", targets_count: 0)
      expect(errors).to eq(['a.exiled_this_turn: must be an object {"each": filter, "controller": ...}'])
      errors = []
      condition = Enjine::Mechanics::Condition.build({ "you_attacked_this_turn" => true }, errors, "c")
      expect([errors, condition.to_s]).to eq([[], "you attacked this turn"])
      expect(Enjine::Mechanics::Condition.build({ "you_attacked_this_turn" => false }, [], "c").to_s).to eq("you didn't attack this turn")
    end
  end

  describe "descriptions" do
    it "describes the new triggers" do
      texts = [{ "leaves_battlefield" => {} },
               { "leaves_battlefield" => { "to" => "graveyard", "subject" => { "each" => "creature", "other" => true } } },
               { "leaves_battlefield" => { "to" => "exile" } },
               { "sacrifices" => { "subject" => { "each" => "artifact", "controller" => "you" } } },
               { "discards" => {} }, { "discards" => { "controller" => "opponent", "card" => "creature", "batched" => true } },
               { "cycles" => { "controller" => "any" } }, { "cycles" => { "card" => "land" } }, { "scries" => {} },
               { "surveils" => { "controller" => "opponent" } },
               { "becomes_untapped" => { "subject" => "attached" } },
               { "put_into" => { "zone" => "graveyard", "card" => "creature", "batched" => true } },
               { "put_into" => { "zone" => "exile", "from" => %w[graveyard battlefield], "controller" => "any" } },
               { "put_into" => { "zone" => "graveyard", "controller" => "opponent" } }].map { trigger(it).to_s }
      expect(texts).to eq(["When this leaves the battlefield", "When another creature is put into a graveyard from the battlefield",
                           "When this is put into exile from the battlefield", "Whenever artifact you control is sacrificed",
                           "Whenever you discard a card", "Whenever an opponent discards one or more creatures",
                           "Whenever a player cycles a card", "Whenever you cycle a land", "Whenever you scry",
                           "Whenever an opponent surveils",
                           "Whenever the attached creature becomes untapped",
                           "Whenever one or more creatures are put into your graveyard from anywhere",
                           "Whenever a card is put into exile from graveyard or battlefield",
                           "Whenever a card is put into an opponent's graveyard from anywhere"])
    end

    it "describes history amounts" do
      left = Enjine::Mechanics::Amount.build({ "left_this_turn" => {} }, [], "a", targets_count: 0)
      sacrificed = Enjine::Mechanics::Amount.build({ "sacrificed_this_turn" => { "each" => "artifact" } }, [], "a", targets_count: 0)
      drawn = Enjine::Mechanics::Amount.build({ "cards_drawn_this_turn" => "you" }, [], "a", targets_count: 0)
      expect([left.to_s, sacrificed.to_s, drawn.to_s])
        .to eq(["the number of objects that left the battlefield this turn", "the number of artifacts sacrificed this turn",
                "the cards drawn this turn of you"])
    end
  end

  describe "matching" do
    let(:game) do
      build_game do
        turn 3, active: "alice", step: :precombat_main
        player("alice") do
          battlefield "Grizzly Bears", "Forest"
          hand "Forest"
        end
        player("bob") { battlefield "Hill Giant" }
      end
    end
    let(:engine) { game.instance_variable_get(:@engine) }
    let(:source) { { "id" => game.state.battlefield[0], "card" => "grizzly_bears", "controller" => 0 } }

    def event(type, **fields) = Enjine::Events.const_get(type).new(**fields)

    it "cycles ignores activations of abilities that aren't cycling" do
      activation = event(:AbilityActivated, player: "alice", object: "x#9", card: "grizzly_bears", source: "x#1",
                                            ability: "printed:0", targets: [])
      expect(trigger({ "cycles" => {} }).match?(engine, activation, source)).to be(false)
    end

    it "keyword-action triggers match the action and the player" do
      scry = event(:KeywordAction, player: "bob", action: "scry", amount: 1)
      expect(trigger({ "scries" => {} }).match?(engine, scry, source)).to be(false)
      expect(trigger({ "scries" => { "controller" => "opponent" } }).match?(engine, scry, source)).to be(true)
      expect(trigger({ "surveils" => { "controller" => "any" } }).match?(engine, scry, source)).to be(false)
    end

    it "discards and put_into check the card filter" do
      forest = game.state.players[0].hand.first
      discard = event(:ZoneChanged, card: "forest", old_id: forest, new_id: "forest#99", owner: "alice", from: "hand",
                                    to: "graveyard", reason: "discard")
      expect(trigger({ "discards" => { "card" => "land" } }).match?(engine, discard, source)).to be(true)
      expect(trigger({ "discards" => { "card" => "creature" } }).match?(engine, discard, source)).to be(false)
      expect(trigger({ "put_into" => { "zone" => "graveyard", "from" => ["library"] } }).match?(engine, discard, source)).to be(false)
      expect(trigger({ "put_into" => { "zone" => "graveyard" } }).match?(engine, discard, source)).to be(true)
    end

    it "leaving-the-battlefield triggers need the permanent's last known information" do
      gone = event(:ZoneChanged, card: "hill_giant", old_id: "hill_giant#77", new_id: "hill_giant#78", owner: "bob",
                                 from: "battlefield", to: "graveyard", reason: "sacrifice")
      expect(trigger({ "leaves_battlefield" => { "subject" => { "each" => "creature" } } }).match?(engine, gone, source)).to be(false)
      expect(trigger({ "sacrifices" => { "subject" => { "each" => "creature" } } }).match?(engine, gone, source)).to be(false)
      expect(trigger({ "becomes_untapped" => {} }).match?(engine, event(:Untapped, object: "gone#1"), source)).to be(false)
    end
  end
end
