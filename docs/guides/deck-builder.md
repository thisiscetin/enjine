# Random deck builder

`Enjine::DeckBuilder` builds random, legal 60-card decks from one or more card
sets, or from a [collection](#building-from-your-collection) of cards you own, in
the colors you ask for. It doesn't look for synergy. It gives every deck
the shape constructed decks share: about 24 lands, a creature count in a typical
range, a curve that leans on cheap cards, and mostly 4-ofs. Those are ranges, not
fixed numbers, and now and then a deck lands outside them on purpose.

```ruby
require "enjine/deck_builder"   # opt-in; also loads enjine/sets

deck = Enjine::DeckBuilder.build(sets: %w[trk], colors: %w[W U], seed: 7)
deck = Enjine::DeckBuilder.build(sets: %w[trk abc], colors: 2, seed: 7)  # two random colors
deck = Enjine::DeckBuilder.build(colors: :any, seed: 7)                  # every set, 1-3 random colors
deck = Enjine::DeckBuilder.build(collection: "mine.json", colors: 2, seed: 7)  # only cards you own

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
  "cards": [ { "name": "Alfa", "types": ["instant"], ...the card DSL...,
               "rarity": "common", "printing": { "set": "trk", "number": "12" } } ] }

A set card is the card DSL plus two optional set-only keys, `rarity` and `printing`.
```

`printing` identifies the printing without depending on any card database: the
set code and the collector number printed on the card. The number is a string,
because collector numbers can contain letters or symbols (`"12a"`, `"★"`).
`Sets::Entry#id` returns `"trk:12"`.

You write every card yourself in the [card DSL](card-data-format.md). Every card
must validate: a set with an invalid card fails to load with
`Sets::InvalidSet`, which names the card's index, its name and each error.

```ruby
require "enjine/sets"

Enjine::Sets.codes                              # => ["abc", "trk"]
set = Enjine::Sets.load("trk")                  # Sets::CardSet: code, name, released_at, cards, entries
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
| `collection:` | none | A `Collection`, a collection document (Hash) or the path of a JSON file. Only owned cards are used, at most the copies owned. Can't be combined with `sets:`; with `cards:`, the extra cards are what entries may resolve against. See [Building from your collection](#building-from-your-collection). |
| `basics:` | `:unlimited` | With `collection:`, `:unlimited` adds as many basic lands as the deck needs, owned or not; `:owned` uses only the basics the collection lists. |

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

It never pads the deck with extra basics beyond the land maximum.

## Command line

```sh
bundle exec exe/enjine --random-deck sets=trk,abc colors=WU seed=7        # prints the deck as JSON
bundle exec exe/enjine --random-deck "sets=trk colors=2 seed=7"           # quoted works too
bundle exec exe/enjine --random-deck sets=standard,colors=any,seed=3      # comma-separated works too
bundle exec exe/enjine --sets-dir path/to/sets --list-sets                # codes, names, Standard legality
bundle exec exe/enjine --deck1 random:sets=trk,colors=WU --deck2 random --p2 random   # play with them
bundle exec exe/enjine --collection mine.json --random-deck colors=2 seed=3   # only cards you own
bundle exec exe/enjine --collection-report mine.json                      # what the collection resolved to
```

Spec keys are `sets` (codes, `all`, or `standard` for the sets that are
Standard-legal today), `colors` (letters, a count, or `any`), `seed`, `size`, and,
with `--collection`, `basics` (`unlimited` or `owned`).
Without `seed`, `--random-deck` uses `--seed`, and `--deck1`/`--deck2` use the game
seed plus the seat index. The game intro prints each deck's recipe. Saved games
that use random decks can't be resumed with `--load` yet, because `--load` only
knows the sample card pool.

## Color balance

In multicolor decks, each new card is drawn from the least represented chosen
color with probability `color_balance` (default 75%), measured in colored mana
symbols. This keeps a two-color deck a real two-color deck: across 400 sample
decks, the weaker color makes up at least 36% of the colored symbols (median
47%). Set it to `0` for unbalanced splashes, or to `100` for strict balance.
Cards outside the chosen colors are never used, and neither are lands that make
off-color mana.

## Building from your collection

A collection is the cards you own, from any number of sets, with how many copies
of each. Pass it as `collection:` and the builder treats it as the whole card
pool: it uses only cards in the collection and never more copies than you own,
and the four-copy rule still applies, so a card's limit is the smaller of its
owned count and 4. Colors, the profile and the seed work as usual.

```ruby
require "enjine/deck_builder"   # also loads enjine/collection

mine = Enjine::Collection.load("mine.json")              # or a Hash, or a bare Array of entries
deck = Enjine::DeckBuilder.build(collection: mine, colors: %w[W U], seed: 7)
deck = Enjine::DeckBuilder.build(collection: "mine.json", colors: 2, seed: 7, basics: :owned)
```

### The collection format

```json
{ "format": 1, "cards": [
  { "name": "Lightning Bolt", "count": 3 },
  { "name": "Some Card", "set": "trk", "count": 2 },
  { "set": "trk", "number": "12", "count": 1 },
  { "name": "Other Card", "set_name": "Star Trek", "count": 4 } ] }
```

`format` is optional and must be `1` when present. Ruby callers can use symbol
keys. Each entry names a card in one of these ways:

| Keys | Meaning |
| --- | --- |
| `name` | The card's name. Names are unique across Magic, so a name alone is enough. Matching ignores case, accents, apostrophes and punctuation (`CardDefinition.slug`), so `"ilsa wall keeper"` finds `Ilsa, Wall Keeper`. |
| `set` + `number` | A printing: the set code and the collector number, as in the set file's `printing`. A number may be written as a JSON number. If you also give `name`, it must match the card at that number. |
| `set` or `set_name` | Restricts a `name` to one set, by code (`"trk"`) or by the set's name (`"Star Trek"`, matched like card names). If both are given they must agree. |

`count` defaults to 1 and must be a positive integer. Entries for the same card
add up, however they name it, so `{ "set": "trk", "number": "12", "count": 2 }`
and `{ "name": "<the card at trk 12>", "count": 2 }` together mean 4 copies.

Entries are resolved against the set files in `sets_dir:` (default `Sets.dir`)
and the extra card data blocks passed as `cards:` (for example
`Enjine::CardPool::Core.cards`). A `name` without a set may match several sets;
the card's definition then comes from the set whose code sorts first (and from
`cards:` only if no set has it). Because of that rule, the entry order
never changes the result: the same collection and seed always give the same deck.

A document that isn't a collection at all (missing file, invalid JSON, no `cards`
array, a bad `count`, an entry with neither `name` nor `set` + `number`) raises
`Enjine::Collection::InvalidCollection`.

### The resolution report

Cards that can't be found are reported, not silently dropped. `Collection#report`
has two lists (string keys, so it is also
the JSON that `--collection-report` prints):

```json
{ "resolved":    [ { "id": "lantern_warden", "name": "Lantern Warden", "set": "fxa", "count": 5 } ],
  "unknown":     [ { "name": "Dawnward Squire", "set": "zzz", "count": 1, "reason": "unknown set \"zzz\"" } ] }
```

- `resolved`: one row per distinct playable card, with the total copies owned.
  `set` is where the definition came from (missing for `cards:`).
- `unknown`: the original entry plus a `reason`: no such card, unknown set or set
  name, no card at that collector number, or a name that doesn't match the number.

Other `Collection` methods:

| Method | Returns |
| --- | --- |
| `entries` | `Collection::Entry` values (`definition`, `count`, `id`, `name`), one per playable card, sorted by id |
| `definitions` | the owned playable `CardDefinition`s, sorted by id |
| `count(card)` | copies owned, by card id or name (0 if none). Basic lands count only if listed. |
| `include?(card)` | whether at least one copy is owned |
| `size` | total playable copies |
| `source` | the file path the collection was loaded from, or `nil` |
| `to_h` | the collection document, normalized (string keys, explicit counts); `Collection.load(c.to_h)` rebuilds it |

### Basic lands

Most players have more basic lands than they ever list, so by default
(`basics: :unlimited`) the builder adds as many basics as the deck needs, whether
or not the collection lists them. It uses a set's own basic lands when the
collection includes them, and the built-in ones otherwise.

With `basics: :owned`, only the listed basics are used, never more than owned.
If a color needs more basics than you own, the shortfall goes to the deck's other
colors that have spare basics. If the owned basics still can't cover the lands,
the builder raises `NotEnoughCards` (`details` include `basics_needed` and
`basics_owned`).

### When the collection is too small

The builder works through the same steps as for sets (more copies, up to what you
own; shifting creatures and other spells; more lands), then raises
`Enjine::DeckBuilder::NotEnoughCards`. With a collection, `details` also has
`collection` (the file name, or the card count) and `colors_without_cards`. A
collection deck must have at least one owned card of every deck color: asking for
`WG` when you own no green cards raises instead of quietly building a mono-white
deck. Random colors (`colors: 2`, `:any`) are only drawn from combinations the
collection can fill.

### Command line

```sh
bundle exec exe/enjine --collection mine.json --random-deck colors=2 seed=3
bundle exec exe/enjine --collection mine.json --random-deck colors=WU basics=owned
bundle exec exe/enjine --collection mine.json --deck1 random:colors=R --deck2 random --p2 random
bundle exec exe/enjine --collection-report mine.json
```

`--collection` applies to `--random-deck` and to every `--deck1`/`--deck2
random:...` seat, and can't be combined with a `sets=` key. `--collection-report`
prints the resolution report as JSON and exits with code 1 if any entry is
unknown, or prints `{"error": ...}` for a
malformed file. Both honor `--sets-dir`. The deck's `description` records the
recipe as `collection=mine.json colors=WU seed=3`.
