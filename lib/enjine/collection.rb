# frozen_string_literal: true

require "json"
require "enjine"
require "enjine/sets"

module Enjine
  # The cards a player owns, possibly from many sets, with quantities (require
  # "enjine/collection"; "enjine/deck_builder" loads it too). A collection document:
  #
  #   { "format": 1, "cards": [
  #     { "name": "Lantern Warden", "count": 3 },                 # by name (unique across Magic)
  #     { "name": "Halo Bearer", "set": "fxb", "count": 2 },      # name, definition taken from that set
  #     { "set": "fxa", "number": "12" },                         # by printing: set code + collector number
  #     { "name": "Fathom Hunter", "set_name": "Tidewild Expanse", "count": 4 } ] }
  #
  # Each entry is resolved against the set files in `sets_dir` and any extra card data
  # blocks in `cards:`. Names match case-insensitively via CardDefinition.slug. `count`
  # defaults to 1, and entries for the same card add up. Cards a set lists as unsupported
  # and cards nobody knows are reported (#report), never silently dropped.
  class Collection
    FORMAT = 1

    # The collection document is missing or malformed (resolution problems go to #report instead).
    class InvalidCollection < Error; end

    # One distinct owned card: its definition and how many copies the collection holds.
    Entry = Data.define(:definition, :count) do
      def id = definition.id
      def name = definition.name
    end

    # A playable definition and where it came from (set code, or nil for `cards:`), ranked for ties.
    Source = Data.define(:definition, :set, :rank)
    private_constant :Source

    attr_reader :source, :entries, :report

    # path_or_hash: a Collection (returned as is), a collection document (Hash), a bare
    # Array of entries, or the path of a JSON file holding a collection document.
    def self.load(path_or_hash, sets_dir: Sets.dir, cards: nil)
      return path_or_hash if path_or_hash.is_a?(Collection)

      doc, source = read(path_or_hash)
      new(doc, sets_dir: sets_dir, cards: cards, source: source)
    end

    def self.read(value)
      return [value, nil] unless value.is_a?(String)
      raise InvalidCollection, "collection file not found: #{value}" unless File.file?(value)

      [JSON.parse(File.read(value)), value]
    rescue JSON::ParserError => e
      raise InvalidCollection, "#{value}: not valid JSON (#{e.message})"
    end
    private_class_method :read

    def initialize(doc, sets_dir: Sets.dir, cards: nil, source: nil)
      @source = source
      @cards = normalize(doc)
      @index = Index.new(Sets.all(dir: sets_dir), cards)
      resolve!
    end

    # Copies owned of a card, by id or (tolerant) name. Basic lands count only if listed.
    def count(card) = @counts.fetch(CardDefinition.slug(card), 0)

    # The owned playable CardDefinitions, one per card, sorted by id.
    def definitions = @entries.map(&:definition)

    # Total copies of playable cards.
    def size = @entries.sum(&:count)

    def include?(card) = count(card).positive?

    # The collection document, normalized (string keys, explicit counts): Collection.load(c.to_h) rebuilds c.
    def to_h = { "format" => FORMAT, "cards" => @cards.map(&:dup) }

    private

    def normalize(doc)
      doc = { "cards" => doc } if doc.is_a?(Array)
      raise InvalidCollection, "a collection must be a JSON object with a \"cards\" array" unless doc.is_a?(Hash)

      doc = doc.transform_keys(&:to_s)
      unless [nil, FORMAT].include?(doc["format"])
        raise InvalidCollection, "unsupported collection format #{doc["format"].inspect} (expected #{FORMAT})"
      end
      raise InvalidCollection, "a collection needs a \"cards\" array" unless doc["cards"].is_a?(Array)

      doc["cards"].each_with_index.map { |raw, i| normalize_entry(raw, i) }.freeze
    end

    def normalize_entry(raw, index)
      raise InvalidCollection, "cards[#{index}]: expected an object, got #{raw.inspect}" unless raw.is_a?(Hash)

      entry = raw.transform_keys(&:to_s).slice("name", "set", "set_name", "number", "count").compact
      entry["count"] = entry.fetch("count", 1)
      unless entry["count"].is_a?(Integer) && entry["count"].positive?
        raise InvalidCollection, "cards[#{index}]: count must be a positive Integer, got #{entry["count"].inspect}"
      end
      unless entry.key?("name") || (entry.key?("set") && entry.key?("number"))
        raise InvalidCollection, "cards[#{index}]: identify the card by \"name\", or by \"set\" and \"number\""
      end

      %w[name set set_name number].each { entry[it] = entry[it].to_s if entry.key?(it) }
      entry.freeze
    end

    def resolve!
      found = {}
      @report = { "resolved" => [], "unsupported" => [], "unknown" => [] }
      @cards.each do |entry|
        outcome = @index.resolve(entry)
        case outcome
        in Source => src
          held = found[src.definition.id]
          best = held.nil? || src.rank < held[0].rank ? src : held[0]
          found[src.definition.id] = [best, (held ? held[1] : 0) + entry["count"]]
        in [:unsupported, unsupported] then @report["unsupported"] << unsupported.merge("count" => entry["count"])
        in [:unknown, reason] then @report["unknown"] << entry.merge("reason" => reason)
        end
      end
      finish(found)
    end

    def finish(found)
      @entries = found.sort.map { |_, (src, n)| Entry.new(definition: src.definition, count: n) }.freeze
      @counts = @entries.to_h { [it.id, it.count] }
      @report["resolved"] = found.sort.map do |id, (src, n)|
        { "id" => id, "name" => src.definition.name, "set" => src.set, "count" => n }.compact
      end
      %w[unsupported unknown].each { |k| @report[k].sort_by! { [CardDefinition.slug(it["name"]), it["set"].to_s, it.to_s] } }
      @report.each_value(&:freeze).freeze
    end

    # Lookup tables over the playable cards of every set (plus extra `cards:`).
    class Index
      def initialize(sets, cards)
        @sets = sets.sort_by(&:code)
        @set_codes = @sets.to_h { [it.code, it] }
        @set_names = @sets.to_h { [CardDefinition.slug(it.name), it.code] }
        @by_name = Hash.new { |h, k| h[k] = [] }
        @printings = {}
        @sets.each_with_index { |set, rank| add_set(set, rank) }
        Array(cards).each do |data|
          definition = data.is_a?(CardDefinition) ? data : CardDefinition.from_h(data)
          @by_name[definition.id] << Source.new(definition: definition, set: nil, rank: @sets.size)
        end
      end

      # A Source, [:unsupported, {"name", "set", "reason"}], or [:unknown, reason].
      def resolve(entry)
        code = restricted_set(entry)
        return [:unknown, code[1]] if code.is_a?(Array)

        entry.key?("number") ? by_printing(entry, code) : by_name(entry, code)
      end

      private

      def add_set(set, rank)
        set.entries.each do |e|
          src = Source.new(definition: e.definition, set: set.code, rank: rank)
          @by_name[e.definition.id] << src
          @printings["#{e.printing["set"]}:#{e.printing["number"]}"] = src if e.printing
        end
      end

      # The set an entry is restricted to (nil: any), or [:unknown, reason].
      def restricted_set(entry)
        code = entry["set"]&.to_s&.downcase
        named = entry["set_name"] && @set_names[CardDefinition.slug(entry["set_name"])]
        return [:unknown, "unknown set #{code.inspect}"] if code && !@set_codes.key?(code)
        return [:unknown, "unknown set name #{entry["set_name"].inspect}"] if entry["set_name"] && named.nil?
        return [:unknown, "set #{code.inspect} and set_name #{entry["set_name"].inspect} disagree"] if code && named && code != named

        code || named
      end

      def by_printing(entry, code)
        src = @printings["#{code}:#{entry["number"]}"]
        return [:unknown, "no printing #{code}:#{entry["number"]} (or it is unsupported)"] if src.nil?
        if entry["name"] && CardDefinition.slug(entry["name"]) != src.definition.id
          return [:unknown, "#{code}:#{entry["number"]} is #{src.definition.name.inspect}, not #{entry["name"].inspect}"]
        end

        src
      end

      def by_name(entry, code)
        slug = CardDefinition.slug(entry["name"])
        candidates = @by_name.fetch(slug, []).select { code.nil? || it.set == code }
        return candidates.min_by(&:rank) unless candidates.empty?

        unsupported(slug, code) || [:unknown, "no card named #{entry["name"].inspect}#{" in #{code}" if code}"]
      end

      def unsupported(slug, code)
        @sets.each do |set|
          next if code && set.code != code

          hit = set.unsupported.find { CardDefinition.slug(it["name"]) == slug }
          next unless hit

          return [:unsupported, { "name" => hit["name"], "set" => set.code, "reason" => reason(hit["missing"]) }]
        end
        nil
      end

      def reason(missing)
        list = Array(missing).map(&:to_s)
        list.empty? ? "not supported by the engine yet" : "needs #{list.join(", ")}"
      end
    end
    private_constant :Index
  end
end
