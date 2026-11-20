# frozen_string_literal: true

module Enjine
  # A player's deck: the card definitions it uses plus the main decklist, and optionally the cards the
  # player owns outside the game.
  #
  #   Deck.from_h({"cards" => [{...Forest...}], "main" => [{"card" => "Forest", "count" => 60}],
  #                "outside" => [{"card" => "Forest", "count" => 2}]})
  #
  # Constructed rules (CR 100.2a): at least 60 cards, at most 4 copies of any card
  # that is not exempt (basic lands). An invalid deck can still be built and edited;
  # it is simply not #valid?, so its player is not ready.
  #
  # A Commander deck (CR 903) names its commander up front, beside the 99 cards of `main`:
  #
  #   Deck.from_h({"cards" => [...], "main" => [...], "commander" => "Wort, the Raidmother"})
  #
  # Which rules apply depends on the game's Format: `errors(format)` checks the deck against it, so the
  # same deck can be valid for one format and not another.
  #
  # Outside the game (CR 400.11, 400.11a): the engine doesn't track a match, so a deck carries the cards
  # its player owns outside the game as `outside`: a constructed sideboard of at most 15 cards (CR 100.4a).
  # The four-copy limit applies to the deck and the outside list together, and outside cards don't count
  # toward the 60. Effects that bring a card into the game from outside it take the card from this list.
  class Deck
    MIN_SIZE = Format::CONSTRUCTED.deck_size.min
    MAX_COPIES = 4
    MAX_OUTSIDE = 15
    NOT_A_COMMANDER = "can't be a commander; it must be a legendary creature, Vehicle or Spacecraft (CR 903.3)"

    attr_reader :catalog, :commander # commander: a definition id or nil (CR 903.3)
    attr_writer :guard

    def self.from_h(hash)
      return hash if hash.is_a?(Deck)
      raise InvalidDeck.new(["deck must be an object"]) unless hash.is_a?(Hash)

      doc = hash.transform_keys(&:to_s).except("name", "description")
      lists = %w[cards main outside].to_h { [it, doc.fetch(it, [])] }
      lists.each { |key, list| raise InvalidDeck.new(["#{key}: must be a list"]) unless list.is_a?(Array) }

      commander = doc["commander"]
      raise InvalidDeck.new(["commander: must be a card name"]) unless commander.nil? || commander.is_a?(String)

      new(cards: lists["cards"], main: lists["main"], outside: lists["outside"], commander: commander)
    end

    def initialize(cards: [], main: [], outside: [], commander: nil)
      @catalog = Catalog.new
      cards.each { @catalog.add(it) }
      @entries = {}
      @outside = {}
      @reference_errors = []
      main.each_with_index { |entry, i| load_entry(entry, i, @entries, "main") }
      outside.each_with_index { |entry, i| load_entry(entry, i, @outside, "outside") }
      load_commander(commander)
    end

    # Ordered {id => count}.
    def entries = @entries.dup.freeze
    def size = @entries.values.sum
    def count(card) = @entries.fetch(CardDefinition.slug(card), 0)

    # Flat list of definition ids, one per physical card.
    def card_ids = @entries.flat_map { |id, n| [id] * n }

    # The cards outside the game: ordered {id => count}, their number, and one definition id per card.
    def outside_entries = @outside.dup.freeze
    def outside_size = @outside.values.sum
    def outside_ids = @outside.flat_map { |id, n| [id] * n }

    # What is wrong with the deck for `format`, as messages (empty when it is legal).
    def errors(format = Format::CONSTRUCTED)
      errs = @reference_errors.dup
      errs.concat(size_errors(format))
      errs << "outside: #{outside_size} cards; at most #{MAX_OUTSIDE} are allowed (CR 100.4a)" if outside_size > MAX_OUTSIDE
      errs.concat(copy_errors(format))
      errs.concat(commander_errors(format))
    end

    def valid?(format = Format::CONSTRUCTED) = errors(format).empty?

    # Adds a card definition this deck can then use.
    def define(definition)
      check_guard!
      @catalog.add(definition)
    end

    def add(card, count: 1)
      check_guard!
      id = resolve!(card)
      @entries[id] = @entries.fetch(id, 0) + positive!(count)
      self
    end

    # Adds cards the player owns outside the game (CR 400.11a).
    def add_outside(card, count: 1)
      check_guard!
      id = resolve!(card)
      @outside[id] = @outside.fetch(id, 0) + positive!(count)
      self
    end

    def remove(card, count: 1)
      check_guard!
      id = resolve!(card)
      have = @entries.fetch(id, 0)
      raise InvalidDeck.new(["cannot remove #{count} #{card}: deck has #{have}"]) if have < positive!(count)

      have == count ? @entries.delete(id) : @entries[id] = have - count
      self
    end

    # Swaps cards between games; no limit on how many.
    def swap(out:, in:, count: 1)
      incoming = binding.local_variable_get(:in)
      check_guard!
      resolve!(incoming)
      remove(out, count: count)
      add(incoming, count: count)
    end

    def to_h
      # Tokens aren't listed: the cards that create them bring them back (two tokens may share a name).
      doc = { "cards" => @catalog.reject(&:token?).map(&:to_h), "main" => @entries.map { |id, n| { "card" => id, "count" => n } } }
      doc["outside"] = @outside.map { |id, n| { "card" => id, "count" => n } } unless @outside.empty?
      doc["commander"] = @commander if @commander
      doc
    end

    private

    # Cards in the deck, its commander included (CR 903.5a).
    def total_size = size + (@commander ? 1 : 0)

    def size_errors(format)
      return [] if format.deck_size.cover?(total_size)

      if format.commander?
        ["deck has #{total_size} cards; exactly #{format.deck_size.min} are required, its commander included (CR 903.5a)"]
      else
        ["deck has #{size} cards; at least #{format.deck_size.min} are required (CR 100.2a)"]
      end
    end

    # The copy limit counts the deck and the cards outside the game together (CR 100.4a), and the commander (CR 903.5b).
    def copy_errors(format)
      counts = @entries.merge(@outside) { |_, a, b| a + b }
      counts.merge!(@commander => 1) { |_, a, b| a + b } if @commander
      counts.filter_map do |id, n|
        defn = @catalog.fetch(id)
        limit = format.copy_limit(defn) # nil: any number (basic lands, "deck_limit": "any")
        next if limit.nil? || n <= limit

        rule = format.commander? ? "CR 903.5b" : "CR 100.2a#{", 100.4a" if @outside.key?(id)}"
        "#{defn.name}: #{n} copies; at most #{limit} are allowed (#{rule})"
      end
    end

    # A Commander deck has a commander that may lead it, and every card's color identity fits it (CR 903.3, 903.5c).
    def commander_errors(format)
      return @commander ? ["commander: only a Commander deck has one (CR 903.3)"] : [] unless format.commander?
      return ["a Commander deck needs a commander (CR 903.3)"] unless @commander

      lead = @catalog.fetch(@commander)
      errs = Format.commander_card?(lead) ? [] : ["#{lead.name}: #{NOT_A_COMMANDER}"]
      (@entries.keys + @outside.keys).uniq.each do |id|
        outside = @catalog.fetch(id).color_identity - lead.color_identity
        next if outside.empty?

        errs << "#{@catalog.fetch(id).name}: color identity #{Mana.symbols(outside)} is not in its commander's (CR 903.5c)"
      end
      errs
    end

    def load_commander(card)
      return if card.nil?
      return @reference_errors << "commander: #{card.inspect} is not defined in cards" unless @catalog.include?(card)

      @commander = CardDefinition.slug(card)
    end

    def load_entry(entry, index, into, list)
      card, count = entry.is_a?(Hash) ? entry.transform_keys(&:to_s).values_at("card", "count") : []
      unless card.is_a?(String) && count.is_a?(Integer) && count.positive?
        return @reference_errors << "#{list}[#{index}]: must be {\"card\": name, \"count\": positive integer}"
      end
      return @reference_errors << "#{list}[#{index}].card: #{card.inspect} is not defined in cards" unless @catalog.include?(card)

      id = CardDefinition.slug(card)
      into[id] = into.fetch(id, 0) + count
    end

    def resolve!(card)
      raise InvalidDeck.new(["card #{card.inspect} is not defined in this deck"]) unless @catalog.include?(card)

      CardDefinition.slug(card)
    end

    def positive!(count)
      raise ArgumentError, "count must be a positive integer" unless count.is_a?(Integer) && count.positive?

      count
    end

    def check_guard!
      @guard&.call
    end
  end
end
