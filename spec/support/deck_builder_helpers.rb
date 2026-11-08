# frozen_string_literal: true

# Fixture sets and synthetic card pools for the deck builder specs.
module DeckBuilderHelpers
  SET_FIXTURES = File.expand_path("../fixtures/sets", __dir__)

  def build_deck(**) = Enjine::DeckBuilder.build(sets_dir: SET_FIXTURES, **)

  # A vanilla creature (or, with type:, a spell that gains 1 life) named after its cost.
  def pool_card(name, cost, type: "creature")
    card = { "name" => name, "mana_cost" => cost, "types" => [type] }
    return card.merge("power" => 2, "toughness" => 2) if type == "creature"

    card.merge("abilities" => [{ "spell" => { "effects" => [{ "gain_life" => { "amount" => 1 } }] } }])
  end

  # A roomy pool: every color, every mana value 1-6, plenty of creatures and other spells.
  def big_pool
    Enjine::Mana::COLORS.flat_map do |c|
      (1..6).flat_map do |mv|
        cost = "#{"{#{mv - 1}}" if mv > 1}{#{c}}"
        [pool_card("#{c} Beast #{mv}a", cost), pool_card("#{c} Beast #{mv}b", cost),
         pool_card("#{c} Charm #{mv}", cost, type: "instant")]
      end
    end
  end

  # Lands, creatures, other spells and nonbasic lands of a generated deck document.
  def deck_stats(doc)
    defs = doc["cards"].to_h { [it["name"], Enjine::CardDefinition.from_h(it)] }
    counts = doc["main"].map { [defs.fetch(it["card"]), it["count"]] }
    sum = ->(&blk) { counts.select { |d, _| blk.call(d) }.sum { it[1] } }
    { lands: sum.call(&:land?), creatures: sum.call(&:creature?),
      others: sum.call { !it.land? && !it.creature? }, counts: counts }
  end
end

RSpec.configure { it.include DeckBuilderHelpers }
