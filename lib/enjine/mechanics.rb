# frozen_string_literal: true

module Enjine
  # Namespace of every registered primitive plus helpers to build them from card data.
  module Mechanics
    module_function

    # Builds a primitive from a data entry. An entry is either a bare name ("tap")
    # or a single-key Hash ({"mana" => {...params}}).
    def build_entry(category, entry, errors, path, **context)
      name, params = split_entry(entry)
      unless name
        errors << "#{path}: must be a name or a single-key object, got #{entry.inspect}"
        return nil
      end

      klass = Enjine.registry.fetch(category, name)
      unless klass
        errors << "#{path}: unknown #{category} #{name.inspect} (supported: #{Enjine.registry.names(category).join(", ")})"
        return nil
      end
      unless params.is_a?(Hash) || klass.respond_to?(:scalar_params?)
        errors << "#{path}.#{name}: parameters must be an object"
        return nil
      end

      klass.build(params, errors, "#{path}.#{name}", **context)
    end

    def split_entry(entry)
      case entry
      when String, Symbol then [entry.to_s, {}]
      when Hash then entry.size == 1 ? [entry.keys.first.to_s, entry.values.first] : nil
      end
    end

    # Reports parameter keys a primitive does not declare.
    def check_keys(params, allowed, errors, path)
      (params.keys.map(&:to_s) - allowed.map(&:to_s)).each do |key|
        errors << "#{path}: unknown parameter #{key.inspect}"
      end
    end

    def fetch_param(params, key)
      params.key?(key.to_s) ? params[key.to_s] : params[key.to_sym]
    end

    def integer_param(params, key, errors, path, default: nil, min: nil)
      value = fetch_param(params, key)
      value = default if value.nil?
      unless value.is_a?(Integer) && (min.nil? || value >= min)
        errors << "#{path}.#{key}: must be an integer#{" >= #{min}" if min}"
        return default || 0
      end
      value
    end

    def list_param(params, key, errors, path)
      value = fetch_param(params, key)
      return [] if value.nil?
      return value if value.is_a?(Array)

      errors << "#{path}.#{key}: must be a list"
      []
    end
  end
end
