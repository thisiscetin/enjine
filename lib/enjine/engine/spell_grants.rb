# frozen_string_literal: true

module Enjine
  class Engine
    # Keywords a spell on the stack has besides its own (CR 113.6, 611.3a): granted by a resolved effect ("those
    # spells gain wither", a `grant` effect on the spell) or by a static ability of a permanent ("Instant and
    # sorcery spells you cast from your hand have cascade", ability `spell_keywords`). A keyword that stands for
    # an ability brings that ability (CR 702.85a: a granted cascade triggers as the spell is cast).
    module SpellGrants
      def with_spell_grants(obj, base)
        return base if obj.ability? || @granting&.include?(obj.id) # a static's filter reads the spell's own keywords

        keywords = granting(obj.id) { granted_spell_keywords(obj) } - base.keywords
        return base if keywords.empty?

        base.with(keywords: (base.keywords + keywords).freeze,
                  abilities: (base.abilities + keywords.flat_map { CardDefinition.keyword_instances(it) }).freeze)
      end

      private

      def granting(id)
        (@granting ||= []) << id
        yield
      ensure
        @granting.delete(id)
      end

      def granted_spell_keywords(obj)
        from_effects = state.effects.select { it["kind"] == "grant" && it["affected"].include?(obj.id) }
                            .flat_map { it["keywords"].map(&:to_sym) }
        from_statics = state.battlefield.flat_map do |id|
          source = object(id)
          next [] unless source.controller == obj.controller

          chars(source).abilities.flat_map do |inst|
            inst.ability.kind == :spell_keywords && inst.ability.applies_to?(self, obj, source) ? inst.ability.keywords : []
          end
        end
        (from_effects + from_statics).uniq
      end
    end

    include SpellGrants
  end
end
