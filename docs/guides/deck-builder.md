# Random deck builder

`Enjine::DeckBuilder` builds random, legal 60-card decks from one or more card
sets, in the colors you ask for. It doesn't look for synergy. It gives every deck
the shape constructed decks share: about 24 lands, a creature count in a typical
range, a curve that leans on cheap cards, and mostly 4-ofs. Those are ranges, not
fixed numbers, and now and then a deck lands outside them on purpose.

```ruby
require "enjine/deck_builder"   # opt-in; also loads enjine/sets

deck = Enjine::DeckBuilder.build(sets: %w[trk], colors: %w[W U], seed: 7)
deck = Enjine::DeckBuilder.build(sets: %w[trk abc], colors: 2, seed: 7)  # two random colors
deck = Enjine::DeckBuilder.build(colors: :any, seed: 7)                  # every set, 1-3 random colors

player = Enjine::Player.new(name: "alice", deck: deck)
player.ready?   # => true
```

The result is a deck document (see the [card data format](card-data-format.md#6-decks)):

```json
{ "name": "Random WU deck",
  "description": "random deck: sets=trk colors=WU seed=7 — 24 lands, 18 creatures, 18 other spells, 17 distinct cards",
  "cards": [ { "name": "Plains", ... }, ... ],
  "main":  [ { "card": "Plains", "count": 12 }, ... ] }
```

The same inputs and seed always give the same deck. The `description` records the
recipe, including colors that were picked at random, so you can rebuild any deck.

## Card sets

Sets are JSON files at `<dir>/<code>.json`. They're opt-in: nothing is loaded
until you ask for it.

```json
{ "format": 1, "code": "trk", "name": "...", "released_at": "2026-11-13",
  "standard_legal_until": "2029-01-19", "standard_legal_until_estimated": true,
  "cards": [ { "card": { ...a card data block in CardDefinition#to_h form... },
               "rarity": "common", "printing": { "set": "trk", "number": "12" } } ],
  "unsupported": [ { "name": "...", "missing": ["flying"] } ] }
```

`printing` identifies the printing without depending on any card database: the
set code and the collector number printed on the card. The number is a string,
because collector numbers can contain letters or symbols (`"12a"`, `"★"`).
`Sets::Entry#id` returns `"trk:12"`.

Only `cards` are playable. Names in `unsupported` are never used. If an entry in
`cards` fails validation, for example because the engine changed, the loader moves
it to `unsupported` along with its errors.

```ruby
require "enjine/sets"

Enjine::Sets.codes                              # => ["abc", "trk"]
set = Enjine::Sets.load("trk")                  # Sets::CardSet: code, name, released_at, cards, entries, unsupported
Enjine::Sets.standard_legal(on: Date.today)     # sets released by then and not yet rotated out
Enjine::Sets.dir = "path/to/sets"               # or ENV["ENJINE_SETS_DIR"]; default lib/enjine/sets
```

Every method also takes `dir:`. `DeckBuilder.build` takes `sets_dir:`.

## Arguments

| Argument | Default | Meaning |
| --- | --- | --- |
| `seed:` | required | Seed for `Enjine::Rng`. Same seed and inputs, same deck. |
| `sets:` | every set in `sets_dir` | Set codes and/or loaded `Sets::CardSet` objects. Order doesn't matter. If the same card name appears in two sets, the copy from the set whose code sorts first is used. |
| `cards:` | none | Extra card data blocks to draw from (for example `Enjine::CardPool::Core.cards`). If you pass only `cards:`, no sets are loaded. |
| `colors:` | `:any` | `%w[W U]`, `"WU"`, a number `1`-`5` (that many random colors), or `:any` (a random count from `random_colors`). |
| `size:` | `60` | Deck size, at least 60. Every count in the profile scales with it. |
| `profile:` | `{}` | Overrides for `DEFAULT_PROFILE`, merged key by key. |
| `sets_dir:` | `Sets.dir` | Where to find sets. |

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
- **Basic lands.** If a set includes its own basic lands, the builder uses them.
  Otherwise it uses built-in ones. Basics are split by the deck's colored mana
  symbols (mana cost pips times copies). Every color with at least one symbol gets
  at least one basic, and the rest are split proportionally.
- **The four-copy rule** (CR 100.2a) applies to every card except basic lands.

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
Enjine::DeckBuilder.build(sets: %w[trk], colors: "R", seed: 1, profile: aggro)
```

## When the pool is too small

A single small set in one color may not have enough cards. The builder works
through these steps in order:

1. It adds more copies of the cards it already picked, up to 4 each.
2. It shifts slots between creatures and other spells. A pool with few creatures
   gets more non-creature spells, and the reverse.
3. It plays more lands, up to the profile's land `outliers` maximum.
4. If the deck still isn't full, it raises `Enjine::DeckBuilder::NotEnoughCards`.
   The message names the sets, the colors, the number of playable cards it found
   and how many cards were missing. `#details` returns the same facts as a Hash.

It never pads the deck with extra basics beyond the land maximum, and it never
uses unsupported cards.

## Command line

```sh
bundle exec exe/enjine --random-deck sets=trk,abc colors=WU seed=7        # prints the deck as JSON
bundle exec exe/enjine --random-deck "sets=trk colors=2 seed=7"           # quoted works too
bundle exec exe/enjine --random-deck sets=standard,colors=any,seed=3      # comma-separated works too
bundle exec exe/enjine --sets-dir path/to/sets --list-sets                # codes, names, Standard legality
bundle exec exe/enjine --deck1 random:sets=trk,colors=WU --deck2 random --p2 random   # play with them
```

Spec keys are `sets` (codes, `all`, or `standard` for the sets that are
Standard-legal today), `colors` (letters, a count, or `any`), `seed` and `size`.
Without `seed`, `--random-deck` uses `--seed`, and `--deck1`/`--deck2` use the game
seed plus the seat index. The game intro prints each deck's recipe. Saved games
that use random decks can't be resumed with `--load` yet, because `--load` only
knows the sample card pool.
