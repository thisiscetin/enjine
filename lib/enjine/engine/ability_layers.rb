# frozen_string_literal: true

module Enjine
  class Engine
    # Layers 5 and 6 of the layer pass (Engine::Characteristics#apply_layers): colors, and abilities gained
    # and lost in timestamp order (CR 613.1e-f, 613.7).
    module AbilityLayers
      # Layer 5 (CR 613.1e): effects that set colors, in timestamp order. Layer 6 (CR 613.1f): keyword counters
      # (CR 122.1b), keywords and abilities from static abilities and resolved effects, and "loses all
      # abilities", applied in timestamp order (CR 613.7): a removal takes away what the object had then, and
      # what is granted later stays. A static ability's timestamp is its source's (CR 613.7a), an effect's is
      # its own (613.7b) and a keyword counter's is when it was put on (613.7c, see #counter_timestamp). A
      # granted ability is referenced "granted:<card>:<ref>" (the granting card's data holds it, see
      # #granted_origin); one a static ability grants ends with "@<granting permanent>", so it can refer to that
      # permanent ("Return Trusty Boomerang to its owner's hand", CR 607.1a, Selector "granter").
      def ability_layers(obj, base, statics, effects)
        base = color_layer(obj, base, statics, effects)
        changes = Mechanics::Counters.keywords(obj.counters).map { |kw| [counter_timestamp(obj, kw.to_s), 0, [:keywords, [kw]]] }
        statics.each do |source, ability|
          next unless ability.ability_changes? && ability.affects?(obj, source, facts(obj, base))

          changes << [timestamp_of(source), 1, [:lose]] if ability.loses_abilities?
          changes << [timestamp_of(source), 1, [:keywords, ability.keywords, granted_instances(source, ability)]]
        end
        effects.each do |effect|
          next unless effect["affected"].include?(obj.id)

          change = case effect["kind"]
                   when "lose_abilities" then [:lose]
                   when "grant" then [:keywords, effect["keywords"].map(&:to_sym)]
                   when "abilities" then [:keywords, [], effect_granted_instances(effect)] # e.g. Effects::Become
                   end
          changes << [effect["timestamp"], 1, change] if change
        end
        return base if changes.empty?

        apply_ability_changes(base, changes.each_with_index.sort_by { |(ts, rank, _), i| [ts, rank, i] }.map { it[0][2] })
      end

      # Folds layer 6 changes in order. Keywords stand for their abilities (prowess is a triggered ability),
      # so a keyword gained, or kept after a removal, brings its instances (CR 613.1f).
      def apply_ability_changes(base, changes)
        keywords = base.keywords
        abilities = base.abilities
        lost = false
        changes.each do |kind, added, granted|
          if kind == :lose
            lost = true
            keywords = []
            abilities = []
          else
            keywords |= added
            abilities += granted unless granted.nil? || granted.empty?
          end
        end
        return base if keywords == base.keywords && abilities.equal?(base.abilities)

        abilities += (lost ? keywords : keywords - base.keywords).flat_map { CardDefinition.keyword_instances(it) }
        base.with(keywords: keywords.freeze, abilities: abilities.freeze)
      end

      # Layer 5: statics (by their source's timestamp) and resolved effects that set colors, the latest last.
      def color_layer(obj, base, statics, effects)
        sets = statics.filter_map do |source, ability|
          [timestamp_of(source), ability.colors] if ability.colors && ability.affects?(obj, source, facts(obj, base))
        end
        effects.each { sets << [it["timestamp"], it["colors"]] if it["kind"] == "colors" && it["affected"].include?(obj.id) }
        return base if sets.empty?

        base.with(colors: Mana::COLORS & sets.max_by(&:first)[1].map(&:to_sym))
      end

      # CR 613.7a, 613.7d: a permanent's timestamp is when it entered the battlefield; its id carries the
      # counter it was created with, which is the timestamp sequence (#next_timestamp!). An Aura or Equipment gets
      # a new one each time it becomes attached (CR 613.7e) and a permanent each time it transforms (CR 613.7g).
      def timestamp_of(obj) = [obj.id[/\d+\z/].to_i, obj.memory["attached_at"].to_i, obj.memory["transformed_at"].to_i].max

      # CR 613.7c: a keyword counter's timestamp is when it was last put on (Engine#add_counters! records it);
      # one it had as it entered (or from a test board) counts as earliest.
      def counter_timestamp(obj, kind) = obj.memory.dig("counter_timestamps", kind) || 0

      # Whether the permanent loses all abilities this layer pass (an effect or a static ability, CR 613.1f).
      def losing_abilities?(obj, statics, effects)
        effects.any? { it["kind"] == "lose_abilities" && it["affected"].include?(obj.id) } ||
          statics.any? { |source, ability| ability.loses_abilities? && ability.affects?(obj, source, facts(obj, @layering[obj.id])) }
      end

      def granted_instances(source, ability)
        defn = definition(source)
        ref = own_ability_instances(source).find { it.ability.equal?(ability) }&.ref or return []
        defn.nested_instances(ref).map { AbilityInstance.new(ref: "granted:#{defn.id}:#{it.ref}@#{source.id}", ability: it.ability) }
      end

      # Abilities a resolved effect grants (layer 6, CR 613.1f): the effect's card holds them under its ref.
      def effect_granted_instances(effect)
        catalog.fetch(effect["card"]).effect_granted(effect["ref"]).map do |inst|
          AbilityInstance.new(ref: "granted:#{effect["card"]}:#{inst.ref}", ability: inst.ability)
        end
      end

      # For a granted ability's reference: [granting card id, its ref in that card], else nil.
      def granted_origin(ref) = AbilityLayers.granted_parts(ref)&.first(2)

      # [granting card id, its ref in that card, granting permanent id or nil] of a granted ability's reference.
      def self.granted_parts(ref)
        return nil unless ref.start_with?("granted:")

        card, inner = ref.delete_prefix("granted:").split(":", 2)
        inner, granter = inner.split("@", 2)
        [card, inner, granter]
      end
    end

    include AbilityLayers
  end
end
