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
  #     "cards": [ { "name": "Alfa", "types": ["instant"], ...card DSL...,
  #                  "rarity": "common", "printing": { "set": "trk", "number": "12" } } ] }
  #
  # Cards are written by hand in Enjine's card DSL (docs/guides/card-data-format.md).
  # Every card must validate: a set with an invalid card fails to load with each
  # error's path, so a mistake is never silently skipped.
  module Sets
    FORMAT = 1
    DEFAULT_DIR = File.join(__dir__, "sets")

    # A loaded set. `cards` are CardDefinitions; `entries` keep the per-card metadata.
    CardSet = Data.define(:code, :name, :released_at, :standard_legal_until, :standard_legal_until_estimated,
                          :entries) do
      def cards = entries.map(&:definition)
      def size = entries.size

      # Standard legality on a date (CR 100.6, format rules): released, and not yet rotated out.
      def standard_legal?(date)
        return false if released_at && date < released_at

        standard_legal_until.nil? || date <= standard_legal_until
      end
    end

    # One playable card of a set. `printing` is vendor-neutral: the set code and the collector
    # number printed on the card ({"set" => "trk", "number" => "12a"}; numbers are strings).
    Entry = Data.define(:definition, :rarity, :printing) do
      # "trk:12": set code and collector number.
      def id = printing && "#{printing["set"]}:#{printing["number"]}"
    end

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

        raise InvalidSet, "#{path}: `cards` must be an array" unless doc.fetch("cards", []).is_a?(Array)

        entries = Array(doc["cards"]).each_with_index.map { |raw, i| entry(raw, "#{path}: cards[#{i}]") }
        CardSet.new(code: doc.fetch("code", File.basename(path, ".json")).to_s.downcase, name: doc["name"],
                    released_at: parse_date(doc["released_at"]),
                    standard_legal_until: parse_date(doc["standard_legal_until"]),
                    standard_legal_until_estimated: doc["standard_legal_until_estimated"] == true,
                    entries: entries.freeze)
      end

      # A card is one object: the card DSL plus the optional set-only keys `rarity` and `printing`.
      def entry(raw, where)
        raise InvalidSet, "#{where}: must be a card object" unless raw.is_a?(Hash)

        printing = raw["printing"]
        raise InvalidSet, "#{where}: printing must be {\"set\", \"number\"}" unless printing.nil? || printing.is_a?(Hash)

        printing = printing.slice("set", "number").transform_values(&:to_s).freeze if printing
        Entry.new(definition: CardDefinition.from_h(raw.except("rarity", "printing")), rarity: raw["rarity"],
                  printing: printing)
      rescue InvalidCardDefinition => e
        raise InvalidSet, "#{where} (#{raw["name"].inspect}): #{e.errors.join("; ")}"
      end
    end
  end
end
