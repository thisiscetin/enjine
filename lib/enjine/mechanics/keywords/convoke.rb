# frozen_string_literal: true

module Enjine
  module Mechanics
    module Keywords
      # CR 702.51a-d: convoke. While paying the spell's total cost, each untapped creature you control may be
      # tapped to pay {1} or one mana of one of its colors (a `pay_cost` option `{type: "convoke", object: id}`).
      class Convoke < Primitive
        primitive :keyword, :convoke,
                  description: "Convoke: while paying this spell's total cost you may tap untapped creatures you " \
                               "control, each paying for {1} or one mana of one of its colors (pay_cost option " \
                               "`{type: \"convoke\", object: id}`). It isn't an alternative or additional cost.",
                  rules: %w[702.51a 702.51b 702.51c 702.51d],
                  example: { "keywords" => ["convoke"] }
      end

      # CR 702.126a-c: improvise. For each generic mana in the spell's total cost, an untapped artifact you control
      # may be tapped instead of paying it (a `pay_cost` option `{type: "improvise", object: id}`).
      class Improvise < Primitive
        primitive :keyword, :improvise,
                  description: "Improvise: while paying this spell's total cost you may tap untapped artifacts you " \
                               "control, each paying for {1} of its generic part (pay_cost option `{type: " \
                               "\"improvise\", object: id}`). It isn't an alternative or additional cost.",
                  rules: %w[702.126a 702.126b 702.126c],
                  example: { "keywords" => ["improvise"] }
      end
    end

    module Abilities
      # "Noncreature spells you cast have improvise." (CR 702.126a, 611.3a): while this permanent is on the
      # battlefield, spells its controller casts matching the card spec `spells` have the listed helper keywords
      # (convoke, improvise) as their costs are paid (Engine::AltCasting#helper_keywords).
      class SpellsHave < Primitive
        KEYWORDS = %w[convoke improvise].freeze

        primitive :ability, :spells_have,
                  description: "Spells you cast matching the card spec `spells` (default: every spell) have `keywords` " \
                               "(convoke and/or improvise) while this permanent is on the battlefield.",
                  rules: %w[702.126a 702.51a 611.3a 604.1],
                  params: { "spells" => "card spec, e.g. {\"not_types\": [\"creature\"]}",
                            "keywords" => "list of convoke, improvise" },
                  example: { "spells_have" => { "spells" => { "not_types" => ["creature"] }, "keywords" => ["improvise"] } }

        attr_reader :spells, :keywords

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[spells keywords], errors, path)
          keywords = Mechanics.fetch_param(params, :keywords)
          unless keywords.is_a?(Array) && !keywords.empty? && (keywords - KEYWORDS).empty?
            errors << "#{path}.keywords: must be a non-empty list of #{KEYWORDS.join(", ")}"
          end
          raw = Mechanics.fetch_param(params, :spells)
          new(raw && CardSpec.build(raw, errors, "#{path}.spells"), Array(keywords).freeze)
        end

        def initialize(spells, keywords)
          super()
          @spells = spells
          @keywords = keywords
          freeze
        end

        def kind = :spells_have
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # The keywords `spell` gets from this ability of a permanent controlled by `controller`.
        def keywords_for(engine, spell, controller)
          spell.controller == controller && (spells.nil? || spells.match?(engine, spell)) ? keywords : []
        end

        def to_s = "#{spells.to_s.sub(/ card\z/, "") if spells} spells you cast have #{keywords.join(", ")}".strip.capitalize
      end
    end
  end
end
