# frozen_string_literal: true

module Enjine
  # Predefined tokens (CR 111.10): referenced by name from card data, e.g.
  # {"create_token": {"token": "Treasure"}}. Other tokens are defined inline.
  module Tokens
    ANY_COLOR = %w[{W} {U} {B} {R} {G}].freeze

    LIBRARY = {
      # CR 111.10a: "{T}, Sacrifice this token: Add one mana of any color."
      "Treasure" => { "name" => "Treasure", "types" => ["artifact"], "subtypes" => ["treasure"],
                      "abilities" => ANY_COLOR.map { { "mana" => { "cost" => %w[tap sacrifice], "produce" => it } } } },
      # CR 111.10f: "{2}, Sacrifice this token: Draw a card."
      "Clue" => { "name" => "Clue", "types" => ["artifact"], "subtypes" => ["clue"],
                  "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{2}" }, "sacrifice"],
                                                     "effects" => [{ "draw" => { "amount" => 1 } }] } }] },
      # CR 111.10b: "{2}, {T}, Sacrifice this token: You gain 3 life."
      "Food" => { "name" => "Food", "types" => ["artifact"], "subtypes" => ["food"],
                  "abilities" => [{ "activated" => { "cost" => [{ "mana" => "{2}" }, "tap", "sacrifice"],
                                                     "effects" => [{ "gain_life" => { "amount" => 3 } }] } }] }
    }.freeze

    def self.fetch(name) = LIBRARY[name]
  end
end
