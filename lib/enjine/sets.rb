# frozen_string_literal: true

require "date"
require "json"
require "enjine"

module Enjine
  # Opt-in card sets (require "enjine/sets"). Each set is one JSON file,
  # `<dir>/<code>.json`, never loaded by default:
  #
  #   { "format": 1, "code": "trk", "name": "...", "released_at": "2026-11-13",
  #     "standard_legal_until": "2029-01-19", "standard_legal_until_estimated": true,
  #     "cards": [ { "card": { ...CardDefinition#to_h... }, "rarity": "common", ... } ],
  #     "unsupported": [ { "name": "...", "missing": ["flying"] } ] }
  #
  # Only `cards` are playable. A `cards` entry that no longer validates (the engine
  # changed) is moved to `unsupported` with its errors instead of failing the load.
  module Sets
    FORMAT = 1
    DEFAULT_DIR = File.join(__dir__, "sets")

    # A loaded set. `cards` are CardDefinitions; `entries` keep the per-card metadata.
    CardSet = Data.define(:code, :name, :released_at, :standard_legal_until, :standard_legal_until_estimated,
                          :entries, :unsupported) do
      def cards = entries.map(&:definition)
      def size = entries.size

      # Standard legality on a date (CR 100.6, format rules): released, and not yet rotated out.
      def standard_legal?(date)
        return false if released_at && date < released_at

        standard_legal_until.nil? || date <= standard_legal_until
      end
    end

    # One playable card of a set.
    Entry = Data.define(:definition, :rarity, :scryfall_id, :collector_number)

    # The set file is missing or malformed.
    class InvalidSet < Error; end

    class << self
      attr_writer :dir

      # The directory sets are read from: Sets.dir = ..., else $ENJINE_SETS_DIR, else lib/enjine/sets.
      def dir = @dir || ENV.fetch("ENJINE_SETS_DIR", DEFAULT_DIR)

      # Codes of every set in the directory, sorted.
      def codes(dir: self.dir) = Dir[File.join(dir, "*.json")].map { File.basename(it, ".json") }.sort

      def load(code, dir: self.dir)
        return code if code.is_a?(CardSet)

        code = code.to_s.downcase
        path = File.join(dir, "#{code}.json")
        raise InvalidSet, "unknown set #{code.inspect} in #{dir} (have: #{codes(dir: dir).join(", ")})" unless File.file?(path)

        parse(JSON.parse(File.read(path)), path)
      rescue JSON::ParserError => e
        raise InvalidSet, "#{path}: not valid JSON (#{e.message})"
      end

      def all(dir: self.dir) = codes(dir: dir).map { load(it, dir: dir) }

      # Sets that are Standard-legal on a date, sorted by code.
      # rubocop:disable-next Naming/MethodParameterName
      def standard_legal(on: Date.today, dir: self.dir) = all(dir: dir).select { it.standard_legal?(on) }

      # Parses a date such as "2029-01-19"; partial dates ("2029-01", "2029") mean their first day.
      def parse_date(value)
        return nil if value.nil?
        return value if value.is_a?(Date)

        match = /\A(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/.match(value.to_s)
        raise InvalidSet, "invalid date #{value.inspect}" unless match

        Date.new(match[1].to_i, (match[2] || 1).to_i, (match[3] || 1).to_i)
      end

      private

      def parse(doc, path)
        raise InvalidSet, "#{path}: a set must be a JSON object" unless doc.is_a?(Hash)
        raise InvalidSet, "#{path}: unsupported format #{doc["format"].inspect} (expected #{FORMAT})" unless doc["format"] == FORMAT

        unsupported = Array(doc["unsupported"]).map { it.slice("name", "missing") }
        entries = Array(doc["cards"]).filter_map { entry(it, unsupported) }
        CardSet.new(code: doc.fetch("code", File.basename(path, ".json")).to_s.downcase, name: doc["name"],
                    released_at: parse_date(doc["released_at"]),
                    standard_legal_until: parse_date(doc["standard_legal_until"]),
                    standard_legal_until_estimated: doc["standard_legal_until_estimated"] == true,
                    entries: entries.freeze, unsupported: unsupported.freeze)
      end

      def entry(raw, unsupported)
        data = raw.is_a?(Hash) ? raw["card"] : nil
        Entry.new(definition: CardDefinition.from_h(data), rarity: raw["rarity"], scryfall_id: raw["scryfall_id"],
                  collector_number: raw["collector_number"])
      rescue InvalidCardDefinition => e
        unsupported << { "name" => data.is_a?(Hash) ? data["name"] : nil, "missing" => e.errors }
        nil
      end
    end
  end
end
