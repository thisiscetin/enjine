# frozen_string_literal: true

module Enjine
  module Mechanics
    # The exceptions of a copy effect (CR 707.9a-b), e.g. {"legendary": false} ("except it isn't
    # legendary") or {"keywords": ["menace"]} ("except it has menace"). They become part of the copy's
    # copiable values, so a copy of the copy has them too (CR 707.2). See Engine::Copies.
    module CopyExcept
      KEYS = %w[legendary keywords types subtypes supertypes name power toughness colors].freeze
      LISTS = { "keywords" => :keyword, "types" => :type, "supertypes" => :supertype }.freeze
      PARAM = "{\"legendary\": false, \"keywords\": [...], \"types\": [...], \"subtypes\": [...], " \
              "\"supertypes\": [...], \"name\": ..., \"power\": n, \"toughness\": n, \"colors\": [...]}"

      module_function

      def build(raw, errors, path)
        return {}.freeze if raw.nil?
        return (errors << "#{path}: must be an object #{PARAM}") && {}.freeze unless raw.is_a?(Hash)

        raw = raw.transform_keys(&:to_s)
        Mechanics.check_keys(raw, KEYS, errors, path)
        out = {}
        errors << "#{path}.legendary: must be false (\"it isn't legendary\")" if raw.key?("legendary") && raw["legendary"] != false
        out["legendary"] = false if raw.key?("legendary")
        LISTS.each { |key, category| out[key] = names(raw[key], category, errors, "#{path}.#{key}") if raw.key?(key) }
        out["subtypes"] = subtypes(raw["subtypes"], errors, "#{path}.subtypes") if raw.key?("subtypes")
        values(raw, out, errors, path)
        out["colors"] = colors(raw["colors"], errors, "#{path}.colors") if raw.key?("colors")
        out.freeze
      end

      # "name", "power", "toughness": values the copy has instead of the copied ones.
      def values(raw, out, errors, path)
        out["name"] = raw["name"] if raw.key?("name")
        errors << "#{path}.name: must be a non-empty string" if raw.key?("name") && !(raw["name"].is_a?(String) && !raw["name"].empty?)
        %w[power toughness].each do |key|
          next unless raw.key?(key)

          errors << "#{path}.#{key}: must be an integer" unless raw[key].is_a?(Integer)
          out[key] = raw[key]
        end
      end

      def names(list, category, errors, path)
        ok = list.is_a?(Array) && !list.empty? && list.all? { Enjine.registry.fetch(category, it.to_s.downcase.tr(" -", "__")) }
        errors << "#{path}: must be a non-empty list of #{category}s (#{Enjine.registry.names(category).join(", ")})" unless ok
        ok ? list.map { it.to_s.downcase.tr(" -", "__") }.freeze : [].freeze
      end

      def subtypes(list, errors, path)
        ok = list.is_a?(Array) && !list.empty? && list.all? { CardDefinition::SUBTYPE_FORMAT.match?(it.to_s) }
        errors << "#{path}: must be a non-empty list of lowercase subtypes" unless ok
        ok ? list.map(&:to_s).freeze : [].freeze
      end

      def colors(list, errors, path)
        ok = list.is_a?(Array) && list.all? { Mana::COLORS.include?(it.to_s.upcase.to_sym) }
        errors << "#{path}: must be a list of W, U, B, R, G ([] for colorless)" unless ok
        ok ? list.map { it.to_s.upcase }.freeze : [].freeze
      end

      def to_s(except)
        return "" if except.empty?

        bits = []
        bits << "not legendary" if except["legendary"] == false
        %w[name power toughness].each { bits << "#{it} #{except[it]}" if except.key?(it) }
        %w[keywords types subtypes supertypes colors].each { bits << "#{it} #{except[it].join("/")}" if except[it] }
        " (except #{bits.join(", ")})"
      end
    end
  end
end
