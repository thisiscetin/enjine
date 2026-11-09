# frozen_string_literal: true

module Enjine
  module Mechanics
    module Abilities
      # "Instant and sorcery spells you cast from your hand have cascade" (CR 604.1, 611.3a): a static ability of a
      # permanent giving keywords to the spells its controller controls on the stack that match `spells` (and were
      # cast `from` / `not_from` a zone). See Engine::SpellGrants.
      class SpellKeywords < Primitive
        primitive :ability, :spell_keywords,
                  description: "Spells you control on the stack matching `spells` (a spell filter; default every " \
                               "spell), cast `from` / `not_from` a zone if given, have the `keywords` (e.g. cascade, " \
                               "which then triggers as such a spell is cast).",
                  rules: %w[604.1 611.3a 702.85a],
                  params: { "spells" => "spell filter", "from" => "zone", "not_from" => "zone",
                            "keywords" => "list of keywords" },
                  example: { "spell_keywords" => { "spells" => { "spell" => { "any_of" => %w[instant sorcery] } },
                                                   "from" => "hand", "keywords" => ["cascade"] } }

        attr_reader :keywords

        def self.build(params, errors, path, **)
          Mechanics.check_keys(params, %w[spells from not_from keywords], errors, path)
          filter = params["spells"] && Mechanics.build_entry(:filter, params["spells"], errors, "#{path}.spells")
          keywords = Array(params["keywords"]).map(&:to_s)
          errors << "#{path}.keywords: needs at least one keyword" if keywords.empty?
          keywords.each { errors << "#{path}.keywords: unknown keyword #{it.inspect}" unless Enjine.registry.fetch(:keyword, it) }
          new(filter, CastFrom.build(params, errors, path), keywords.map(&:to_sym).freeze)
        end

        def initialize(filter, zones, keywords)
          super()
          @filter = filter
          @zones = zones
          @keywords = keywords
          freeze
        end

        def kind = :spell_keywords
        def mana_ability? = false
        def allowed_types = nil
        def try_effects = []

        # `spell`: a spell on the stack controlled by the controller of `source`.
        def applies_to?(engine, spell, source)
          return false if spell.ability? || !@zones.match?(engine.cast_origin(spell))

          @filter.nil? || @filter.match_for?(engine, spell.id, source.controller, source.id)
        end

        def to_s = "#{@filter || "Spells"} you cast#{@zones} have #{keywords.join(", ")}"
      end
    end
  end
end
