# frozen_string_literal: true

# Validation of the turn-structure primitives: phasing, may_not_untap, additional_land_plays, become,
# additional_triggers effects, return_choice and counters_placed first_time_this_turn.
RSpec.describe "Turn structure primitives validation" do
  def errors_for(card)
    Enjine::CardDefinition.from_h(card)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  def creature(*abilities, keywords: [])
    { "name" => "Test Drifter", "mana_cost" => "{1}", "types" => ["creature"], "subtypes" => ["rogue"],
      "power" => 1, "toughness" => 1, "keywords" => keywords, "abilities" => abilities }
  end

  def spell(*effects)
    { "name" => "Test Flux", "mana_cost" => "{1}", "types" => ["sorcery"],
      "abilities" => [{ "spell" => { "effects" => effects } }] }
  end

  def become(params) = creature({ "activated" => { "cost" => ["tap"], "effects" => [{ "become" => params.merge("to" => "self") }] } })

  it "accepts the parameterless statics and the phasing keyword" do
    defn = Enjine::CardDefinition.from_h(creature("may_not_untap", "additional_land_plays", "cant_phase_in",
                                                  keywords: ["phasing"]))
    expect(defn.abilities.map(&:to_s)).to include("You may choose not to untap it during your untap step",
                                                  "You may play an additional land on each of your turns",
                                                  "Permanents can't phase in")
    expect(defn.keyword?(:phasing)).to be(true)
    expect(errors_for(creature({ "may_not_untap" => { "x" => 1 } }))).to include(a_string_matching(/abilities\[0\]/))
  end

  it "phase_out takes a selector" do
    defn = Enjine::CardDefinition.from_h(spell({ "phase_out" => { "to" => { "each" => "creature" } } }))
    expect(defn.abilities.first.try_effects.first.to_s).to start_with("phase out")
    expect(errors_for(spell({ "phase_out" => { "to" => "self", "amount" => 2 } }))).to include(a_string_matching(/phase_out/))
  end

  describe "become (CR 611.2, 613)" do
    it "builds types, base power/toughness and granted abilities with their own refs" do
      defn = become("creature_types" => ["scout"], "base_power_toughness" => { "power" => 3, "toughness" => 4 },
                    "abilities" => ["additional_land_plays"], "duration" => "indefinite")
             .then { Enjine::CardDefinition.from_h(it) }
      effect = defn.abilities.first.try_effects.first
      expect(effect.to_s).to eq("becomes scout, base 3/4, \"You may play an additional land on each of your turns\" → itself")
      expect(defn.effect_granted(effect.ref).map(&:ref)).to eq(["#{effect.ref}:0"])
      expect(defn.ability("#{effect.ref}:0").kind).to eq(:additional_land_plays)
      expect(Enjine::CardDefinition.from_h(become("creature_types" => ["scout"])).abilities.first.try_effects.first.to_s)
        .to end_with("until end of turn → itself")
    end

    it "reports path-addressed errors" do
      expect(errors_for(become({}))).to include(a_string_matching(/become: needs at least one of types/))
      expect(errors_for(become("creature_types" => [], "duration" => "forever")))
        .to include(a_string_matching(/become\.creature_types: must be a non-empty list/),
                    a_string_matching(/become\.duration: must be one of end_of_turn, indefinite/))
      expect(errors_for(become("base_power_toughness" => 3)))
        .to include(a_string_matching(/become\.base_power_toughness: must be/))
      expect(errors_for(become("base_power_toughness" => { "power" => 1, "toughness" => -1, "x" => 0 })))
        .to include(a_string_matching(/base_power_toughness\.toughness/), a_string_matching(/base_power_toughness/))
      expect(errors_for(become("abilities" => ["may_not_untap"])))
        .to include(a_string_matching(/become\.abilities\[0\]: only triggered, mana, play_from/))
    end
  end

  it "additional_triggers needs a duration" do
    effect = lambda { |params|
      creature({ "activated" => { "cost" => ["tap"], "targets" => ["creature"], "effects" => [{ "additional_triggers" => params }] } })
    }
    defn = Enjine::CardDefinition.from_h(effect.call("to" => { "target" => 0 }, "duration" => "while_source_tapped"))
    expect(defn.abilities.first.try_effects.first.to_s).to include("trigger an additional time")
    expect(errors_for(effect.call("to" => { "target" => 0 })))
      .to include(a_string_matching(/additional_triggers\.duration: must be one of while_source_tapped/))
  end

  it "return_choice reads like sacrifice_choice" do
    defn = Enjine::CardDefinition.from_h(spell({ "return_choice" => { "filter" => "land" } }))
    expect(defn.abilities.first.try_effects.first.to_s).to eq("you returns 1 land of their choice to its owner's hand")
    expect(errors_for(spell({ "return_choice" => { "count" => 0 } })))
      .to include(a_string_matching(/return_choice\.filter: required/), a_string_matching(/return_choice\.count/))
  end

  it "counters_placed takes first_time_this_turn" do
    trigger = lambda { |flag|
      creature({ "triggered" => { "when" => { "counters_placed" => { "counter" => "charge", "first_time_this_turn" => flag } },
                                  "effects" => [{ "draw" => { "amount" => 1 } }] } })
    }
    expect(Enjine::CardDefinition.from_h(trigger.call(true)).abilities.first.to_s).to include("for the first time each turn")
    expect(errors_for(trigger.call("yes"))).to include(a_string_matching(/first_time_this_turn: must be true or false/))
  end
end
