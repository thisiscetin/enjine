# frozen_string_literal: true

# Data validation and descriptions of split second, persist, undying, offspring, impending, miracle, craft, collect
# evidence, flashback for its mana cost, warp zones, void and cycling costs.
RSpec.describe "Keyword primitives (data)" do
  def ability(entry, extra = {})
    card = { "name" => "Spec Data Card", "mana_cost" => "{1}{R}", "types" => ["sorcery"], "abilities" => [entry] }.merge(extra)
    Enjine::CardDefinition.from_h(card).ability_instances.first.ability
  end

  def errors_for(entry, extra = {})
    ability(entry, extra)
    []
  rescue Enjine::InvalidCardDefinition => e
    e.errors
  end

  it "registers the keywords split second, persist and undying (CR 702.61a, 702.79a, 702.93a)" do
    %w[split_second persist undying].each { expect(Enjine.registry.fetch(:keyword, it)).not_to be_nil }
    defn = Enjine::CardDefinition.from_h("name" => "Spec Kw", "mana_cost" => "{R}", "types" => ["creature"],
                                         "power" => 1, "toughness" => 1, "keywords" => %w[persist undying])
    expect(defn.ability_instances.map(&:ref)).to eq(%w[keyword:persist keyword:undying])
    expect(defn.ability_instances.map { it.ability.to_s }.join).to include("dies")
  end

  it "describes offspring, impending, miracle and craft (CR 702.175a, 702.176a, 702.94a, 702.167a)" do
    expect(ability({ "offspring" => { "cost" => "{2}" } }, "types" => ["creature"], "power" => 1, "toughness" => 1).to_s)
      .to eq("Offspring {2}")
    expect(ability({ "miracle" => { "cost" => "{R}" } }).to_s).to eq("Miracle {R}")
    craft = ability({ "craft" => { "cost" => "{2}", "materials" => { "count" => 2 } } }, "types" => ["artifact"])
    expect(craft.to_s).to include("Exile 2 cards from among permanents you control")
    one = ability({ "craft" => { "cost" => "{2}", "materials" => {} } }, "types" => ["artifact"])
    expect(one.to_s).to include("Exile a card from among")
  end

  it "rejects bad data with paths (CR 702.175a, 702.176a, 702.167a, 701.59a, 702.185a)" do
    expect(errors_for({ "impending" => { "amount" => "two", "cost" => "{G}" } }, "types" => ["creature"], "power" => 1,
                                                                                 "toughness" => 1).join).to include("impending.amount")
    expect(errors_for({ "craft" => { "cost" => 2 } }, "types" => ["artifact"]).join).to include("craft.cost")
    expect(errors_for({ "additional_cost" => { "cost" => [{ "collect_evidence" => "six" }] } }).join).to include("collect_evidence")
    expect(errors_for({ "warp" => { "cost" => "{R}", "from" => [] } }, "types" => ["creature"], "power" => 1,
                                                                       "toughness" => 1).join).to include("warp.from")
    expect(errors_for({ "flashback" => { "cost" => "mana_cost", "extra" => 1 } }).join).to include("flashback")
  end

  it "a flashback for its mana cost gives no cast method to a card without a mana cost (CR 118.6, 702.34a)" do
    flashback = ability({ "flashback" => { "cost" => "mana_cost" } })
    expect(flashback.own_mana_cost?).to be(true)
    expect(flashback.alternative?).to be(true)
    expect(flashback.method_for("printed:0")).to be_nil
    expect(ability({ "flashback" => { "cost" => "{R}" } }).method_for("printed:0").dig("alt", "cost")).to eq("{R}")
  end

  it "describes void and its negation (CR 207.2c)" do
    expect(Enjine::Mechanics::Condition.build({ "void" => true }, [], "c").to_s).to start_with("void")
    expect(Enjine::Mechanics::Condition.build({ "void" => false }, [], "c").to_s).to start_with("not void")
  end

  it "describes cycling costs (CR 702.29a)" do
    expect(ability({ "cycling" => { "cost" => "{X}{G}" } }).to_s).to eq("Cycling {X}{G}")
    expect(errors_for({ "cycling" => {} }).join).to include("cycling.cost: required")
  end
end
