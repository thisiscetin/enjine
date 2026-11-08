# frozen_string_literal: true

require "enjine"
require "enjine/sets"

module Enjine
  # Builds random, legal, *plausibly shaped* constructed decks from one or more card
  # sets (require "enjine/deck_builder"). No synergy: just the proportions every
  # 60-card deck shares, drawn as ranges with occasional outliers.
  #
  #   Enjine::DeckBuilder.build(sets: %w[trk], colors: %w[W U], seed: 7)   # explicit colors
  #   Enjine::DeckBuilder.build(sets: %w[trk abc], colors: 2, seed: 7)     # two random colors
  #   Enjine::DeckBuilder.build(colors: :any, seed: 7)                     # every set in Sets.dir
  #
  # Returns a deck document ({"name", "description", "cards", "main"}) that
  # Enjine::Player.new(name:, deck:) accepts. Same inputs and seed, same deck.
  # Randomness comes only from Enjine::Rng, and every candidate list is sorted by
  # card id before sampling, so the result does not depend on file or hash order.
  class DeckBuilder
    # The chosen sets and colors don't have enough playable cards. #details says what was missing.
    class NotEnoughCards < Error
      attr_reader :details

      def initialize(message, details)
        @details = details.freeze
        super(message)
      end
    end

    # Default deck shape. Every count is for 60 cards and scales linearly with `size:`.
    # Counts are drawn from `range` with a triangular weight peaking at `center`; with
    # probability `outlier_chance` (percent) a count is instead drawn uniformly from
    # the wider `outliers` range, so the odd 20-land aggro or 27-land control deck appears.
    DEFAULT_PROFILE = {
      # 60-card constructed decks overwhelmingly play 22-26 lands (24 is the classic
      # "40%" baseline); very low curves dip to ~20, heavy control reaches ~27.
      lands: { range: 22..26, center: 24, outliers: 20..27 },
      # Creature counts vary the most between archetypes: ~14 for midrange/control
      # shells, up to ~24 for creature aggro; spell-heavy or creature-only extremes are rarer.
      creatures: { range: 14..24, center: 18, outliers: 10..28 },
      # Non-creature spells (instants, sorceries, artifacts, enchantments,
      # planeswalkers) take the remaining slots.
      outlier_chance: 10,
      # Relative weight of each mana value when choosing the next distinct card
      # (0 counts as 1, 6 means 6+): most cards cost 1-3, fewer 4, few 5+.
      curve: { 1 => 16, 2 => 28, 3 => 24, 4 => 16, 5 => 9, 6 => 7 },
      # Copies of each distinct non-basic card: constructed decks are mostly
      # 4-ofs, with some 2-3-ofs and a few singletons.
      copies: { 4 => 50, 3 => 20, 2 => 20, 1 => 10 },
      # Non-basic land copies (when the sets have lands that fit the colors):
      # a mono-color deck plays a few utility lands, a multicolor deck several duals.
      nonbasic_lands: { mono: 0..4, multi: 2..8 },
      # Number of colors when `colors: :any`: two-color decks are the most common.
      random_colors: { 1 => 30, 2 => 50, 3 => 20 }
    }.freeze

    BASIC_LAND_NAMES = { W: "Plains", U: "Island", B: "Swamp", R: "Mountain", G: "Forest" }.freeze
    # Used when no chosen set ships its own basic lands (CR 305.6: the land type grants the mana ability).
    BASIC_LANDS = BASIC_LAND_NAMES.transform_values do |name|
      { "name" => name, "types" => ["land"], "supertypes" => ["basic"], "subtypes" => [name.downcase] }.freeze
    end.freeze
    BASE_SIZE = 60

    attr_reader :colors, :sets, :size, :profile

    # sets:     set codes and/or Sets::CardSet objects (nil: every set in sets_dir unless cards: is given)
    # cards:    extra card data blocks / CardDefinitions to draw from (e.g. CardPool::Core.cards)
    # colors:   %w[W U], "WU", an Integer 1-5 (random colors), or :any (random count, see random_colors)
    def self.build(seed:, sets: nil, cards: nil, colors: :any, size: BASE_SIZE, profile: {}, sets_dir: Sets.dir)
      new(seed: seed, sets: sets, cards: cards, colors: colors, size: size, profile: profile, sets_dir: sets_dir).build
    end

    # The colors of a card: the colored symbols in its mana cost (CR 105.2, 202.2), in WUBRG order.
    def self.colors_of(definition)
      cost = definition.mana_cost
      cost ? Mana::COLORS.select { cost.colored.key?(it) } : []
    end

    # The colors a deck must be able to produce to use a card: its colors plus the colored
    # symbols in its activation costs, so an off-color activated ability never sneaks in.
    def self.required_colors(definition)
      costs = definition.abilities.flat_map { it.respond_to?(:costs) ? it.costs : [] }.select { it.respond_to?(:mana_cost) }
      symbols = costs.flat_map { it.mana_cost.colored.keys }
      Mana::COLORS.select { colors_of(definition).include?(it) || symbols.include?(it) }
    end

    # The colors of mana a permanent's mana abilities produce, in WUBRG order ({C} excluded).
    def self.produced_colors(definition)
      produced = definition.mana_abilities.flat_map(&:produce)
      Mana::COLORS.select { produced.include?(it) }
    end

    # Colorless cards fit every deck (CR 105.2c); others fit when all their colors are deck colors.
    def self.fits?(definition, colors)
      required_colors(definition).all? { colors.include?(it) }
    end

    # Normalizes "WU", %w[w u] or [:W, :U] to [:W, :U] in WUBRG order.
    def self.parse_colors(value)
      letters = value.is_a?(Array) ? value.map(&:to_s) : value.to_s.delete(", ").chars
      symbols = letters.map { it.strip.upcase.to_sym }
      bad = symbols - Mana::COLORS
      raise ArgumentError, "unknown color #{bad.join(", ")} (use W U B R G)" unless bad.empty?
      raise ArgumentError, "choose at least one color" if symbols.empty?

      Mana::COLORS.select { symbols.include?(it) }
    end

    def initialize(seed:, sets: nil, cards: nil, colors: :any, size: BASE_SIZE, profile: {}, sets_dir: Sets.dir)
      raise ArgumentError, "size must be an Integer of at least #{Deck::MIN_SIZE}" unless size.is_a?(Integer) && size >= Deck::MIN_SIZE

      @rng = Rng.from_seed(seed)
      @seed = seed
      @size = size
      @profile = merge_profile(profile)
      @sets = load_sets(sets, cards, sets_dir)
      @pool = build_pool(cards)
      @colors = resolve_colors(colors)
    end

    def build
      lands = scaled(sample(@profile[:lands]))
      creatures = scaled(sample(@profile[:creatures])).clamp(0, @size - lands)
      @creatures = {}
      @others = {}
      lands += fill_spells(lands, creatures)
      document(lands)
    end

    private

    # --- inputs ---------------------------------------------------------------------------------------

    def merge_profile(overrides)
      unknown = overrides.keys.map(&:to_sym) - DEFAULT_PROFILE.keys
      raise ArgumentError, "unknown profile keys: #{unknown.join(", ")}" unless unknown.empty?

      DEFAULT_PROFILE.to_h do |key, default|
        value = overrides.fetch(key, overrides.fetch(key.to_s, default))
        [key, default.is_a?(Hash) ? default.merge(value) : value]
      end
    end

    def load_sets(sets, cards, dir)
      sets = Sets.codes(dir: dir) if sets.nil? && cards.nil?
      loaded = Array(sets).map { Sets.load(it, dir: dir) }.uniq(&:code).sort_by(&:code)
      raise ArgumentError, "no card sets found in #{dir}" if loaded.empty? && cards.nil?

      loaded
    end

    # Every playable definition, one per id (the first set in code order wins a duplicate name).
    def build_pool(cards)
      definitions = @sets.flat_map(&:cards) + Array(cards).map { CardDefinition.from_h(it) }
      definitions.uniq(&:id).sort_by(&:id)
    end

    def resolve_colors(value)
      case value
      when :any, "any", nil then random_colors(weighted(@profile[:random_colors]))
      when Integer then random_colors(value)
      when /\A\d\z/ then random_colors(value.to_i)
      else self.class.parse_colors(value)
      end
    end

    # A uniformly random color combination among those the pool can actually fill.
    def random_colors(count)
      raise ArgumentError, "a deck has 1 to 5 colors, not #{count}" unless (1..5).cover?(count)

      combos = Mana::COLORS.combination(count).to_a
      viable = combos.select { viable?(it) }
      return viable[@rng.rand(viable.size)] unless viable.empty?

      combos.max_by { capacity(spells_for(it)) } # nothing fits: the closest one, which then explains what's missing
    end

    def viable?(colors)
      spells = spells_for(colors)
      colors.all? { |c| spells.any? { self.class.colors_of(it).include?(c) } } &&
        capacity(spells) >= @size - scaled(@profile[:lands][:outliers].max)
    end

    def spells_for(colors) = @pool.select { it.castable? && self.class.fits?(it, colors) }
    def capacity(definitions) = definitions.sum { it.deck_limit_exempt? ? @size : Deck::MAX_COPIES }

    # --- spells ---------------------------------------------------------------------------------------

    # Fills the non-land slots. Scarcity, in order: more copies of chosen cards (up to 4),
    # then the creature/other split moves, then up to the outlier land maximum. Returns extra lands.
    def fill_spells(lands, creature_target)
      spells = spells_for(@colors)
      creature_pool, other_pool = spells.partition(&:creature?)
      others_target = @size - lands - creature_target
      creatures = pick(creature_pool, creature_target, @creatures)
      others = pick(other_pool, others_target + (creature_target - creatures), @others)
      missing = @size - lands - creatures - others
      missing -= pick(creature_pool, creatures + missing, @creatures) - creatures if missing.positive?
      extra = missing.clamp(0, [scaled(@profile[:lands][:outliers].max) - lands, 0].max)
      not_enough!(creature_pool, other_pool, lands + extra, missing - extra) if missing > extra
      extra
    end

    # Adds distinct cards (by curve weight) to `chosen` until it holds `target` cards, then
    # tops up copies. Returns the number of cards in `chosen`.
    def pick(pool, target, chosen)
      candidates = pool.reject { chosen.key?(it.id) }
      filled = chosen.values.sum
      missing_colors.each do |color|
        colored = candidates.select { self.class.colors_of(it).include?(color) }
        filled = take(colored.empty? ? nil : by_curve(colored), candidates, chosen, filled, target)
      end
      filled = take(by_curve(candidates), candidates, chosen, filled, target) while filled < target && !candidates.empty?
      top_up(chosen, filled, target)
    end

    def take(definition, candidates, chosen, filled, target)
      return filled if definition.nil? || filled >= target

      candidates.delete(definition)
      copies = [weighted(@profile[:copies]), target - filled].min
      chosen[definition.id] = [copies, 1].max
      filled + chosen[definition.id]
    end

    def top_up(chosen, filled, target)
      while filled < target
        open = chosen.keys.select { chosen[it] < Deck::MAX_COPIES }
        break if open.empty?

        open.each do |id|
          break if filled >= target

          chosen[id] += 1
          filled += 1
        end
      end
      filled
    end

    # Multicolor decks start with one card of each color not yet represented.
    def missing_colors
      have = (@creatures.keys + @others.keys).flat_map { self.class.colors_of(definition(it)) }
      @colors.size > 1 ? @colors - have : []
    end

    def by_curve(candidates)
      buckets = candidates.group_by { it.mana_cost.mana_value.clamp(1, 6) }
      weights = @profile[:curve].select { |mv, w| buckets.key?(mv) && w.positive? }
      bucket = weights.empty? ? buckets.keys.min : weighted(weights)
      cards = buckets.fetch(bucket)
      cards[@rng.rand(cards.size)]
    end

    def not_enough!(creature_pool, other_pool, lands, missing)
      details = { sets: @sets.map(&:code), colors: @colors.join, size: @size, lands: lands,
                  creatures_available: creature_pool.size, others_available: other_pool.size,
                  max_spell_copies: capacity(creature_pool + other_pool), missing: missing }
      raise NotEnoughCards.new(
        "cannot build a #{@size}-card #{@colors.join} deck from #{source_label}: only #{creature_pool.size} creature and " \
        "#{other_pool.size} other non-land cards are playable in those colors (at most #{details[:max_spell_copies]} copies), " \
        "#{missing} short of the #{@size - lands} non-land cards needed even with #{lands} lands. " \
        "Add sets or colors, or lower the profile's ranges.", details
      )
    end

    # --- lands ----------------------------------------------------------------------------------------

    def land_counts(total)
      nonbasic = pick_nonbasic_lands(total)
      basics = split_basics(total - nonbasic.values.sum)
      [basics, nonbasic]
    end

    def pick_nonbasic_lands(total)
      pool = @pool.select { nonbasic_land?(it) }
      range = @profile[:nonbasic_lands][@colors.size == 1 ? :mono : :multi]
      want = [scaled(range.min + @rng.rand(range.max - range.min + 1)), total / 2].min
      chosen = {}
      take(by_land_weight(pool), pool, chosen, chosen.values.sum, want) while chosen.values.sum < want && !pool.empty?
      chosen
    end

    def nonbasic_land?(definition)
      definition.land? && !definition.supertype?(:basic) && !definition.mana_abilities.empty? &&
        self.class.produced_colors(definition).all? { @colors.include?(it) }
    end

    # Weight 4 for lands that produce two or more deck colors (duals), 2 for one color, 1 for colorless-only.
    def by_land_weight(pool)
      weights = pool.map { [1, 2, 4][self.class.produced_colors(it).size.clamp(0, 2)] }
      roll = @rng.rand(weights.sum)
      pool.each_with_index { |defn, i| (roll -= weights[i]).negative? && (return defn) }
    end

    # Basic lands split by the deck's colored mana symbols: every color that has symbols
    # gets at least one, the rest is proportional (largest remainder, ties in WUBRG order).
    def split_basics(count)
      pips = @colors.to_h { |c| [c, spell_entries.sum { |defn, n| defn.mana_cost.colored.fetch(c, 0) * n }] }
      pips = @colors.to_h { [it, 1] } if pips.values.sum.zero?
      split = pips.to_h { |c, n| [c, n.positive? && count >= pips.count { it[1].positive? } ? 1 : 0] }
      rest = count - split.values.sum
      total = pips.values.sum
      shares = pips.to_h { |c, n| [c, Rational(rest * n, total)] }
      shares.each { |c, share| split[c] += share.floor }
      leftover = count - split.values.sum
      shares.sort_by { |c, share| [-(share - share.floor), @colors.index(c)] }.first(leftover).each { split[it[0]] += 1 }
      split.reject { |_, n| n.zero? }
    end

    # --- output ---------------------------------------------------------------------------------------

    def document(lands)
      basics, nonbasic = land_counts(lands)
      main = basics.map { |color, n| [basic_land(color), n] } +
             sorted(nonbasic) + sorted(@creatures) + sorted(@others)
      { "name" => "Random #{@colors.join} deck",
        "description" => description(lands, main),
        "cards" => main.map { it[0].to_h },
        "main" => main.map { |defn, n| { "card" => defn.name, "count" => n } } }
    end

    def description(lands, main)
      "random deck: sets=#{@sets.map(&:code).join(",")} colors=#{@colors.join} seed=#{@seed} — " \
        "#{lands} lands, #{@creatures.values.sum} creatures, #{@others.values.sum} other spells, " \
        "#{main.size} distinct cards"
    end

    def sorted(chosen)
      chosen.map { |id, n| [definition(id), n] }.sort_by { |defn, _| [defn.mana_cost&.mana_value || 0, defn.name] }
    end

    def spell_entries = sorted(@creatures) + sorted(@others)

    def basic_land(color)
      name = BASIC_LAND_NAMES.fetch(color)
      @pool.find { it.id == CardDefinition.slug(name) && it.supertype?(:basic) } || CardDefinition.from_h(BASIC_LANDS[color])
    end

    def definition(id) = (@by_id ||= @pool.to_h { [it.id, it] }).fetch(id)

    # --- randomness -----------------------------------------------------------------------------------

    def sample(spec)
      return uniform(spec[:outliers]) if @rng.rand(100) < @profile[:outlier_chance]

      range = spec[:range]
      center = spec.fetch(:center) { (range.min + range.max) / 2 }
      spread = [center - range.min, range.max - center].max + 1
      weighted(range.to_h { [it, spread - (it - center).abs] })
    end

    def uniform(range) = range.min + @rng.rand(range.max - range.min + 1)
    def scaled(count) = Rational(count * @size, BASE_SIZE).round

    # A key of `weights` ({key => Integer weight}), chosen proportionally; keys are tried in order.
    def weighted(weights)
      weights = weights.select { |_, w| w.positive? }
      raise ArgumentError, "profile weights must include a positive weight" if weights.empty?

      roll = @rng.rand(weights.values.sum)
      weights.each { |key, w| (roll -= w).negative? && (return key) }
    end

    def source_label = @sets.empty? ? "the given cards" : @sets.map(&:code).join("+")
  end
end
