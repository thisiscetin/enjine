# frozen_string_literal: true

module Enjine
  # An ability as an object currently has it, with a stable reference:
  #   "printed:<i>"          the i-th ability in the card data
  #   "intrinsic:<subtype>"  granted by a subtype rule (e.g. a basic land type, CR 305.6)
  # Later: "keyword:<name>", "granted:<effect>:<i>". References are what options and
  # stack objects carry, so they stay valid when abilities are granted or removed.
  AbilityInstance = Data.define(:ref, :ability)

  # An object's characteristics after continuous effects (CR 109.3, 613).
  # Rules code asks these questions via Engine#chars, never the printed CardDefinition.
  Characteristics = Data.define(:name, :mana_cost, :colors, :types, :supertypes, :subtypes, :keywords, :abilities,
                                :power, :toughness, :loyalty) do
    def self.printed(defn)
      new(name: defn.name, mana_cost: defn.mana_cost, colors: defn.colors, types: defn.types, supertypes: defn.supertypes,
          subtypes: defn.subtypes, keywords: defn.keywords, abilities: defn.ability_instances,
          power: defn.power, toughness: defn.toughness, loyalty: defn.loyalty)
    end

    def type?(type) = types.include?(type)
    def legendary? = supertypes.include?(:legendary)
    def creature? = types.include?(:creature)
    def planeswalker? = types.include?(:planeswalker)
    def land? = types.include?(:land)
    def keyword?(keyword) = keywords.include?(keyword)

    def ability(ref) = abilities.find { it.ref == ref }&.ability
    def mana_abilities = abilities.select { it.ability.mana_ability? }
    def activated_abilities = abilities.select { %i[activated loyalty].include?(it.ability.kind) }
    def triggered_abilities = abilities.select { it.ability.kind == :triggered }
  end
end
