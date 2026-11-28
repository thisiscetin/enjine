# frozen_string_literal: true

module Enjine
  # A card's color identity (CR 903.4): the colors of the mana symbols in its mana cost and rules, plus its
  # color indicator, characteristic-defining colors and the mana its basic land types make (CR 903.5d), over
  # every face of the card (CR 903.4d-e). Reminder text doesn't count (CR 903.4c), and the engine never reads
  # text: the symbols are found in the card's *data* (costs, produced mana, kicker, ...), not in `rules_text`.
  # A face may state its identity by hand with "color_identity" instead, for the odd card the data can't tell.
  module ColorIdentity
    SKIPPED_KEYS = %w[name rules_text rarity printing color_identity].freeze
    BASIC_LAND_COLORS = { plains: :W, island: :U, swamp: :B, mountain: :R, forest: :G }.freeze
    # A mana ability ({"mana": {...}}) or an add_mana effect: what it adds is written in its own keys.
    MANA_KEYS = %w[mana add_mana].freeze
    COLOR_WORDS = { "white" => :W, "blue" => :U, "black" => :B, "red" => :R, "green" => :G }.freeze

    module_function

    # WUBRG-ordered colors of a whole card.
    def of(definition)
      colors = definition.faces.flat_map { face_colors(it) }
      Mana::COLORS.select { colors.include?(it) }.freeze
    end

    def face_colors(face)
      face.declared_color_identity || (face.colors + land_colors(face) + symbols(face.source.except("faces")))
    end

    # The colors of the mana a basic land type makes (CR 305.6, 903.5d).
    def land_colors(face) = face.subtypes.filter_map { BASIC_LAND_COLORS[it] }

    # The colors named by every mana symbol in the card's data, hybrid and monocolored hybrid symbols included.
    def symbols(node)
      case node
      when Hash then node.flat_map { |key, value| entry_symbols(key, value) }
      when Array then node.flat_map { symbols(it) }
      when String then node.scan(Mana::SYMBOL).flatten.flat_map { it.scan(/[WUBRG]/).map(&:to_sym) }
      else []
      end
    end

    def entry_symbols(key, value)
      return [] if SKIPPED_KEYS.include?(key)
      return mana_symbols(value) if MANA_KEYS.include?(key) && value.is_a?(Hash)

      symbols(value)
    end

    # Mana a card adds counts by the symbols its text would print (CR 903.4): `produce`, and the colors of a choice
    # among some ("Add {B} or {G}": `"color": "any_one", "colors": ["B", "G"]`). Mana "of the chosen color" prints
    # no symbol, so it adds nothing: neither `"color": "chosen"` nor one fixed color gated on the color chosen for
    # the permanent (a Thriving land's {"produce": "{W}", "only_if": {"chosen": "white"}}).
    def mana_symbols(ability)
      rest = symbols(ability.except("produce", "colors"))
      return rest if chosen_color?(ability)

      choice = %w[any_one any].include?(ability["color"]) ? Array(ability["colors"]).map { it.to_s.to_sym } : []
      rest + symbols(ability["produce"]) + (choice & Mana::COLORS)
    end

    # Whether the mana is the color chosen for the permanent: only_if {"chosen": <color word>} naming every color
    # it produces.
    def chosen_color?(ability)
      condition = ability["only_if"]
      color = condition.is_a?(Hash) && COLOR_WORDS[condition["chosen"]]
      return false unless color

      produced = symbols(ability["produce"])
      !produced.empty? && produced.all?(color)
    end
  end
end
