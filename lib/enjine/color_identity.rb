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
      when Hash then node.flat_map { |key, value| SKIPPED_KEYS.include?(key) ? [] : symbols(value) }
      when Array then node.flat_map { symbols(it) }
      when String then node.scan(Mana::SYMBOL).flatten.flat_map { it.scan(/[WUBRG]/).map(&:to_sym) }
      else []
      end
    end
  end
end
