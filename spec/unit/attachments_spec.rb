# frozen_string_literal: true

RSpec.describe "Aura and Equipment card data (CR 301.5, 303.4, 702.5, 702.6)" do
  def card(**fields) = { "name" => "Test Gear", "mana_cost" => "{1}" }.merge(fields.transform_keys(&:to_s))
  def build(**) = Enjine::CardDefinition.from_h(card(**))

  def errors_for(**)
    build(**)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  let(:equip) { { "equip" => { "cost" => [{ "mana" => "{2}" }] } } }

  it "builds an Equipment with equip and an 'equipped creature' static" do
    defn = build(types: ["artifact"], subtypes: ["equipment"],
                 abilities: [{ "static" => { "affects" => "attached", "pump" => { "power" => 2 }, "keywords" => ["Trample"] } }, equip])
    static, ability = defn.abilities
    expect(static).to have_attributes(attached?: true, power: 2, toughness: 0, keywords: [:trample])
    expect(static.to_s).to eq("the attached permanent gets +2/+0 and trample")
    expect(ability).to have_attributes(kind: :activated, sorcery_speed?: true)
    expect(ability.to_s).to eq("Equip {2}")
    expect(defn.to_h["abilities"].last).to eq(equip)
  end

  it "gives an Aura an implicit targeted spell ability from its enchant ability (CR 115.1b, 303.4a)" do
    defn = build(types: ["enchantment"], subtypes: ["aura"],
                 abilities: [{ "enchant" => { "permanent" => { "any_of" => %w[artifact creature] } } }])
    expect(defn.spell_ability.targets.size).to eq(1)
    expect(defn.spell_ability.kind).to eq(:aura_spell)
    expect(defn.abilities.first.to_s).to eq("Enchant artifact or creature")
    expect(build(types: ["enchantment"], subtypes: ["aura"], abilities: [{ "enchant" => "creature" }]).abilities.first.to_s)
      .to eq("Enchant creature")
  end

  it "reports path-addressed errors for misused attachment data" do
    expect(errors_for(types: ["artifact"], abilities: [equip])).to include("abilities[0]: only Equipment have equip (CR 702.6a)")
    expect(errors_for(types: ["artifact"], subtypes: ["equipment"], abilities: [{ "equip" => { "cost" => [] } }]))
      .to include("abilities[0].equip.cost: must be a non-empty list")
    expect(errors_for(types: ["artifact"], subtypes: ["equipment"], abilities: [{ "equip" => { "cost" => [], "when" => 1 } }]))
      .to include("abilities[0].equip: unknown parameter \"when\"")
    expect(errors_for(types: ["enchantment"], subtypes: ["aura"]))
      .to include("abilities: an Aura needs exactly one enchant ability (CR 303.4a, 702.5a)")
    expect(errors_for(types: ["enchantment"], abilities: [{ "enchant" => "creature" }]))
      .to include("abilities[0]: only Auras have enchant (CR 702.5a)")
    expect(errors_for(types: ["enchantment"], subtypes: ["aura"], abilities: [{ "enchant" => "player" }]))
      .to include(a_string_starting_with("abilities[0].enchant: must be a filter for permanents"))
    expect(errors_for(types: ["enchantment"], subtypes: ["aura"], abilities: [{ "enchant" => "spell" }]))
      .to include(a_string_starting_with("abilities[0].enchant: must be a filter for permanents"))
    expect(errors_for(types: ["creature"], subtypes: ["aura"], power: 1, toughness: 1, abilities: [{ "enchant" => "creature" }]))
      .to include(a_string_matching(/aura is only valid for enchantment cards/))
    expect(errors_for(types: ["artifact"], subtypes: ["equipment"], abilities: [{ "static" => { "affects" => "attached" } }]))
      .to include("abilities[0].static: needs pump and/or keywords (or creature_types, abilities)")
  end

  it "attach takes a single target (CR 301.5c)" do
    spell = ->(to) { { "spell" => { "targets" => ["creature"], "effects" => [{ "attach" => { "to" => to } }] } } }
    expect(errors_for(types: ["sorcery"], abilities: [spell.call("you")]))
      .to include(a_string_starting_with("abilities[0].spell.effects[0].attach.to: must be {\"target\": n}"))
    expect(build(types: ["sorcery"], abilities: [spell.call({ "target" => 0 })]).spell_ability.effects.first.to_s)
      .to eq("attach to target #1")
  end

  it "'attached' selects what the source is attached to, and is a trigger subject" do
    selector = Enjine::Mechanics::Selector.build("attached", [], "to", targets_count: 0)
    expect(selector.to_s).to eq("the attached permanent")
    errors = []
    trigger = Enjine::Mechanics.build_entry(:trigger, { "attacks" => { "subject" => "attached" } }, errors, "when")
    expect(errors).to be_empty
    expect(trigger.to_s).to eq("Whenever the attached creature attacks")
  end
end
