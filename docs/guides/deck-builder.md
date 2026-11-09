# Random deck builder

`Enjine::DeckBuilder` builds random, legal 60-card decks from a card pool, in the
colors you ask for. It knows nothing of sets: the pool is whatever cards you give
it, from one set, several, or your own collection. It doesn't look for synergy. It
gives every deck the shape constructed decks share: about 24 lands, a creature
count in a typical range, a curve that leans on cheap cards, and mostly 4-ofs.
Those are ranges, not fixed numbers, and now and then a deck lands outside them on
purpose.

Create one builder and keep it: it holds the pool in memory, validated once, and
builds as many decks as you ask for, each with its own colors, size and seed.

```ruby
require "enjine/deck_builder"   # opt-in

builder = Enjine::DeckBuilder.new(cards)         # card data blocks and/or CardDefinitions
deck = builder.build(colors: %w[W U], seed: 7)   # explicit colors
deck = builder.build(colors: 2, seed: 8)         # two random colors
deck = builder.build(seed: 9)                    # 1-3 random colors (see random_colors)

player = Enjine::Player.new(name: "alice", deck: deck)
player.ready?   # => true
```

The result is a deck document (see the [card data format](card-data-format.md#6-decks)):

```json
{ "name": "Random WU deck",
  "description": "random deck: colors=WU seed=7 — 24 lands, 18 creatures, 18 other spells, 17 distinct cards",
  "cards": [ { "name": "Plains", ... }, ... ],
  "main":  [ { "card": "Plains", "count": 12 }, ... ] }
```

The same pool, arguments and seed always give the same deck, whatever the order
of the pool. The `description` records the colors (including ones picked at
random) and the seed, so you can rebuild any deck.

## The pool

Each entry is a card data block (the [card DSL](card-data-format.md), optionally
with `rarity` and `printing`) or a `CardDefinition`. To build only from cards you
own, give counts:

```ruby
mine = Enjine::DeckBuilder.new([
  { "card" => { "name" => "Lightning Bolt", ... }, "count" => 3 },   # you own 3
  { "card" => { "name" => "Grizzly Bears", ... }, "count" => 9 },    # 9, but a deck holds at most 4
  { "name" => "Hill Giant", ... }                                    # no count: as many as a deck may hold
])
mine.count("Lightning Bolt")   # => 3 (nil: uncapped, 0: not in the pool)
mine.cards                     # the pool's CardDefinitions, sorted by id
```

Entries for the same card add up. Two different definitions under one name raise
`Enjine::CatalogConflict`; the same card with a different `rarity` or `printing` (a
reprint) is the same card. A deck never holds more copies than the pool has, and
basic lands are always available, owned or not.

## Arguments to `build`

| Argument | Default | Meaning |
| --- | --- | --- |
| `seed:` | required | Seed for `Enjine::Rng`. Same seed and pool, same deck. |
| `colors:` | `:any` | `%w[W U]`, `"WU"`, a number `1`-`5` (that many random colors), or `:any` (a random count from `random_colors`). |
| `size:` | `60` | Deck size, at least 60. Every count in the profile scales with it. |
| `profile:` | `{}` | Overrides for `DEFAULT_PROFILE`, merged key by key. |
| `including:` | `[]` | Pool cards (names or ids) the deck must hold, as many copies as allowed up to 4. Each must fit the colors (a land: make only deck colors). A deck with included cards may name colors the pool has no other card of; those bring only basics. |

Random colors are drawn uniformly from the color combinations the pool can fill:
each color needs at least one card, and there must be enough cards in total. If no
combination works, the builder takes the one closest to working, and the error it
raises then tells you what's missing.

## Which cards fit

- **Spells.** A card fits when the colored symbols in its mana cost (its colors,
  CR 105.2, 202.2) and in its activation costs are all deck colors. Colorless
  cards fit every deck. Cards without a mana cost aren't used, because they can't
  be cast.
- **Non-basic lands.** A land fits when all the colored mana it can produce is in
  the deck colors (colorless is fine). A land that produces no mana isn't used.
  Lands that produce two deck colors are picked more often.
- **Basic lands.** Always available, whatever the pool holds. If the pool has its own
  basic lands, the builder uses them; otherwise it uses built-in ones. Basics are split by the deck's colored mana
  symbols (mana cost pips times copies). Every color with at least one symbol gets
  at least one basic, and the rest are split proportionally.
- **The four-copy rule** (CR 100.2a) applies to every card except basic lands, and an
  owned count caps it further.

## The default profile

All counts are for 60 cards (`Enjine::DeckBuilder::DEFAULT_PROFILE`).

| Key | Default | Why |
| --- | --- | --- |
| `lands` | `range: 22..26, center: 24, outliers: 20..27` | Most 60-card decks play 22-26 lands, and 24 is the classic baseline. Very low curves go down to about 20, and heavy control decks go up to about 27. |
| `creatures` | `range: 14..24, center: 18, outliers: 10..28` | Creature counts vary the most between archetypes. |
| `outlier_chance` | `10` | The percent chance that a count is drawn uniformly from `outliers` instead of the triangular distribution over `range` peaking at `center`. |
| `curve` | `{1=>16, 2=>28, 3=>24, 4=>16, 5=>9, 6=>7}` | The weight of each mana value when picking the next card. 0 counts as 1, and 6 means 6 or more. |
| `copies` | `{4=>50, 3=>20, 2=>20, 1=>10}` | How many copies of each card: mostly 4-ofs, some 2-ofs and 3-ofs, a few 1-ofs. |
| `nonbasic_lands` | `mono: 0..4, multi: 2..8` | How many non-basic land copies to include, if any fit. Never more than half the lands. |
| `random_colors` | `{1=>30, 2=>50, 3=>20}` | How many colors `colors: :any` picks. |

Non-creature spells (instants, sorceries, artifacts, enchantments and
planeswalkers) fill whatever slots are left.

```ruby
aggro = { lands: { range: 20..23, center: 21 }, creatures: { range: 22..28, center: 25 },
          curve: { 1 => 30, 2 => 35, 3 => 20, 4 => 10, 5 => 5, 6 => 0 } }
builder.build(colors: "R", seed: 1, profile: aggro)
```

## When the pool is too small

A small pool in one color may not have enough cards. The builder works through
these steps in order:

1. It adds more copies of the cards it already picked, up to 4 each (or the count
   owned).
2. It shifts slots between creatures and other spells. A pool with few creatures
   gets more non-creature spells, and the reverse.
3. It plays more lands, up to the profile's land `outliers` maximum.
4. If the deck still isn't full, it raises `Enjine::DeckBuilder::NotEnoughCards`.
   The message names the colors, the pool's size, the number of playable cards it
   found and how many cards were missing. `#details` returns the same facts as a Hash
   (`pool`, `colors`, `size`, `colors_without_cards`, ...).

Every deck color needs at least one playable card: asking for `"WG"` from a pool
without green cards raises `NotEnoughCards` naming the missing color. It never pads
the deck with extra basics beyond the land maximum.

## Command line

`--pool FILE` is a JSON array of pool entries, loaded once for the whole run.

```sh
bundle exec exe/enjine --pool examples/pool.json --random-deck colors=WU seed=7   # prints the deck as JSON
bundle exec exe/enjine --pool examples/pool.json --random-deck "colors=2 seed=7"  # quoted works too
bundle exec exe/enjine --pool examples/pool.json --random-deck colors=any,seed=3  # comma-separated works too
bundle exec exe/enjine --pool examples/pool.json --deck1 random:colors=WU --deck2 random --p2 random   # play with them
```

Spec keys are `colors` (letters, a count, or `any`), `seed` and `size`. Without
`seed`, `--random-deck` uses `--seed`, and `--deck1`/`--deck2` use the game seed
plus the seat index. The game intro prints each deck's recipe. A game saved with
`s FILE` carries its cards, so `--load` resumes it without the pool.

## Color balance

In multicolor decks, each new card is drawn from the least represented chosen
color with probability `color_balance` (default 75%), measured in colored mana
symbols. This keeps a two-color deck a real two-color deck: across 400 sample
decks, the weaker color makes up at least 36% of the colored symbols (median
47%). Set it to `0` for unbalanced splashes, or to `100` for strict balance.
Cards outside the chosen colors are never used, and neither are lands that make
off-color mana.
