# Enjine

**A deterministic, rules-accurate Magic: The Gathering engine for Ruby, built for the Standard format.**

Enjine runs two-player Magic: The Gathering games by the
[Comprehensive Rules](https://magic.wizards.com/en/rules) (pinned to the version
effective **2026-11-06**). It turns every moment of the game into an explicit,
atomic decision with a list of legal options. That makes it a solid base for
simulations, bots and reinforcement learning, or for a game client.

**Scope: Standard.** The target is every mechanic used by the cards of the current
Standard-legal sets, plus the core rules every game needs. Mechanics that exist
only on cards outside Standard are out of scope until a Standard card needs them
(see [Scope](#scope) below).

- **Strict rules.** Turn structure, priority, the stack, casting with manual mana
  payment, combat, state-based actions, London mulligan. Code and tests cite rule
  numbers.
- **Data-first cards.** Cards are JSON data blocks, not code. Unknown mechanics
  are rejected with precise, path-addressed errors.
- **Atomic decisions.** One small choice at a time (cast → target → tap → pay),
  each one cancellable until the costs are paid.
- **Deterministic.** Seeded PCG32 RNG: the same seed and the same decisions give
  the same game, bit for bit. Export or import any moment, even mid-cast.
- **Hidden information handled properly.** Per-player views and histories, plus an
  omniscient observer view.
- **No runtime dependencies.** Plain Ruby 4.0.

> Status: early (0.1), but broad. The goal is that every card of the Standard-legal
> sets can be written in the DSL and plays by the rules; most can today. Progress
> and what's pending are in [docs/plans/standard.md](docs/plans/standard.md).
> [`SUPPORTED.md`](SUPPORTED.md) (generated from the code) lists every primitive.

## Scope

Enjine targets **two-player Standard**. Coverage against the 2026-11-06
Comprehensive Rules:

| Part of the rules | Coverage |
| --- | --- |
| Core game rules (CR 1–6: turns, priority, the stack, casting, combat, state-based actions, layers, replacement and prevention, copies) | essentially complete for two players |
| Mechanics on Standard-legal cards (14 sets, Foundations to Star Trek) | the goal: nearly all expressible today; the remaining gaps are listed per set in [docs/plans/standard.md](docs/plans/standard.md#mechanics-gaps) |
| Keyword actions (CR 701), all of Magic's history | about half (36 of 71): every one used in Standard |
| Keyword abilities (CR 702), all of Magic's history | about a third (62 of 195): every one used in Standard |
| Special card rules (CR 703–734) | those Standard uses (double-faced, meld, Sagas, Adventures, Classes, Omens, station, prepare); not face-down cards, split or flip cards, levelers, Prototype, Cases, mutate, day/night, the monarch or the initiative |

**Not supported:** mechanics that appear only on cards outside Standard (for
example morph, madness, delve, persist, infect, ninjutsu, cumulative upkeep),
battles and dungeons, multiplayer and casual variants (Commander, Planechase,
Archenemy), ante, matches and sideboarding. A card using an unsupported mechanic
can't be written: validation rejects it with an error naming the unknown key.
Some older keywords can still be written from existing primitives (investigate is
"create a Clue token"). When a set enters Standard, its new mechanics are added;
when a set rotates out, its mechanics stay.

## Card sets

Enjine ships no real cards. You write each card yourself in the
[card DSL](docs/guides/card-data-format.md), a JSON block naming what the card
does, and Enjine validates it:

```json
{ "name": "Alfa", "mana_cost": "{1}{U}{U}", "types": ["instant"],
  "abilities": [ { "spell": { "targets": ["spell"], "effects": [ { "counter": { "to": { "target": 0 } } } ] } } ] }
```

Nothing reads rules text. A card may also carry its `"rarity"` and its
`"printing": { "set": "trk", "number": "12" }`; the rules ignore both. Put cards in a
deck's `cards`, or hand a pool of them (a whole set, several sets, or the cards you own)
to the [deck builder](docs/guides/deck-builder.md) for random decks.

By the gap census, Star Trek, Reality Fracture, Avatar, Spider-Man and Aetherdrift
have no known gaps. The other Standard sets have a few single-card gaps, listed
per set in [docs/plans/standard.md](docs/plans/standard.md#mechanics-gaps).

To check a folder of your cards, run `bundle exec exe/enjine --verify DIR` (add
`--games N`, `--seed S` or `--json`). It validates every card, then plays
rules-monitored games with random decks built from them, and reports invalid cards,
cards that were never used in play, and any rules finding.

## Set support

| Set | Creature | Instant | Sorcery | Artifact | Enchantment | Land | Planeswalker | Battle | Kindred |
|---|---|---|---|---|---|---|---|---|---|
| Star Trek (`trk`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Reality Fracture (`fra`) | — | — | — | — | — | — | — | n/a | n/a |
| The Hobbit (`hob`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Marvel Super Heroes (`msh`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Secrets of Strixhaven (`sos`) | — | — | — | — | — | — | — | n/a | n/a |
| Teenage Mutant Ninja Turtles (`tmt`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Lorwyn Eclipsed (`ecl`) | — | — | — | — | — | — | — | n/a | — |
| Avatar: The Last Airbender (`tla`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Spider-Man (`spm`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Edge of Eternities (`eoe`) | — | — | — | — | — | — | — | n/a | n/a |
| Final Fantasy (`fin`) | — | — | — | — | — | — | n/a | n/a | n/a |
| Tarkir: Dragonstorm (`tdm`) | — | — | — | — | — | — | — | n/a | n/a |
| Aetherdrift (`dft`) | — | — | — | — | — | — | — | n/a | n/a |
| Foundations (`fdn`) | — | — | — | — | — | — | — | n/a | n/a |

✓ means every card of that type in the set was written in the DSL, validated, and
used in rules-monitored play with `enjine --verify`. The card data used for these
checks is kept outside this repository. n/a means the set has no card of that type.

## Try it: play both sides in your terminal

```sh
git clone https://github.com/thisiscetin/enjine && cd enjine
bundle install
# hot-seat: you play both players, with two of the example decks
bundle exec exe/enjine --deck1 examples/decks/gruul_beats.json --deck2 examples/decks/azorius_walkers.json
# play against a random opponent, with a random red-green deck from a card pool
bundle exec exe/enjine --pool examples/pool.json --deck1 random:colors=RG --deck2 examples/decks/izzet_spells.json --p2 random
bundle exec exe/enjine --pool examples/pool.json --random-deck colors=WU seed=7   # print a random deck
```

[`examples/`](examples) holds ready-to-play deck documents (each carries the cards it
uses) and `pool.json`, a JSON array of cards to build random decks from. They're not
part of the gem.

```
━━ Turn 3 · alice's turn · Main 1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Beginning › ▶MAIN 1 › Combat › Main 2 › End
  Priority: alice
  BOB — life 18 · library 50 · hand 6 · graveyard 0
    Lands:     Plains [plains#88], Island [island#97]
    Permanents:
      Glory Seeker · 2/2 [glory_seeker#101]
  ALICE — life 20 · library 51 · hand 5 · graveyard 1
    Lands:     Mountain [mountain#99], Forest [forest#104], Forest [forest#110]
    Permanents:
      Grizzly Bears · 2/2 [grizzly_bears#106]
    Hand:      Lightning Bolt {R} [lightning_bolt#93], Hill Giant {3}{R} [hill_giant#108], …
  Stack (top first): empty

▶ ALICE must act: priority  (Turn 3 · alice's turn · Main 1)
   1) Pass priority
   2) Cast Lightning Bolt {R}
   3) Tap Mountain for mana ({T}: Add {R}.)
   …
alice> 2
```

When passing priority is your only option, the CLI passes for you. The board
header shows whose turn it is and the current phase and step. Commands: a number
picks an option, `o` toggles the observer view (both hands and library order), `h` shows the
history, `u` undoes, `s FILE` saves, `--load FILE` resumes, and `?` shows help.

## Use it as a library

```ruby
require "enjine"
require "enjine/deck_builder"   # opt-in

# Enjine knows no cards: a deck document carries its own (see examples/decks).
alice = Enjine::Player.new(name: "alice", deck: JSON.parse(File.read("examples/decks/gruul_beats.json")))
# One long-lived builder over any card pool; build as many decks as you like.
builder = Enjine::DeckBuilder.new(JSON.parse(File.read("examples/pool.json")))
bob   = Enjine::Player.new(name: "bob", deck: builder.build(colors: %w[W U], seed: 7))
setup = Enjine::Setup.new(alice, bob)    # compile once ...
game  = setup.new_game(seed: 42)         # ... spawn many games cheaply

until game.over?
  decision = game.pending_decision       # player, kind, options, details
  game.submit(decision.options.sample)
end

game.result          # => {"winner" => "bob", "reason" => "life"}
game.view_for("alice")
game.history_for("alice")
game.export          # JSON snapshot; Enjine::Game.import(json, catalog: setup.catalog)
```

The full API for callers (decisions, views, events, saving and replaying, bots and RL, errors) is in [docs/guides/api.md](docs/guides/api.md).

## Cards are data

```json
{ "name": "Lightning Bolt", "mana_cost": "{R}", "types": ["instant"],
  "abilities": [{ "spell": {
    "targets": ["any_target"],
    "effects": [{ "deal_damage": { "amount": 3, "to": { "target": 0 } } }] } }] }
```

```json
{ "name": "Vessa, Rally Captain", "mana_cost": "{2}{W}{W}", "types": ["planeswalker"], "loyalty": 3,
  "abilities": [{ "loyalty": { "cost": 1, "effects": [
    { "pump": { "power": 1, "toughness": 1, "to": { "each": "creature", "controller": "you" } } }] } }] }
```

Validate cards in bulk:

```sh
bundle exec exe/enjine --validate cards.json   # JSON report, exit code 1 if any card is invalid
```

The [card DSL guide](docs/guides/card-data-format.md) lists every field, ability,
effect and filter with examples.

## Where things are

```
lib/enjine.rb               entry point (the engine; deck_builder, cli and docs are opt-in requires)
lib/enjine/
  game.rb                   public API: pending_decision, submit, apply, views, history, export/import
  setup.rb player.rb deck.rb  players, decks and the compiled two-player Setup
  card_definition.rb        card data block -> validated, immutable definition
  engine.rb engine/         the rules state machine: turns, priority, casting, stack, combat, damage, layers
  steps.rb                  the 12 steps of a turn and their turn-based actions
  decisions/ actions/       every kind of question a player is asked / every action at priority
  mechanics/                one primitive per mechanic: types, keywords, abilities, costs, effects, filters
  state.rb snapshot.rb      plain-data game state, export/import and its consistency checks
  events.rb view.rb history.rb  typed events, per-player views and histories
  cli.rb cli/               the interactive terminal client
  deck_builder.rb           OPT-IN random constructed decks from a card pool
  agents/ fuzz.rb docs.rb   random player, invariant-checking fuzzer, docs generator
exe/enjine                  CLI executable
examples/                   ready-to-play decks and a card pool (not in the gem)
spec/unit spec/integration spec/e2e   the three test levels; spec/support/scenario.rb is the board DSL
spec/fixtures/cards/        the cards specs and fuzz play with, one file per mechanic family
docs/                       design, architecture, guides, generated reference, CR coverage checklist
SUPPORTED.md                generated list of everything the engine supports
```

## Documentation

| Document | What it covers |
| --- | --- |
| [SUPPORTED.md](SUPPORTED.md) | every supported type, keyword, ability, cost, effect and filter (generated) |
| [docs/reference/](docs/reference) | parameters and examples for every primitive and decision (generated) |
| [docs/guides/card-data-format.md](docs/guides/card-data-format.md) | the card DSL: fields, abilities, effects, validation, DB schema |
| [docs/guides/api.md](docs/guides/api.md) | the library API for callers: games, decisions, views, events, save/replay, bots and RL, deck builder, errors |
| [docs/guides/deck-builder.md](docs/guides/deck-builder.md) | random decks from any card pool (a set, your collection), in chosen or random colors (`--pool`, `--random-deck`) |
| [docs/guides/adding-a-mechanic.md](docs/guides/adding-a-mechanic.md) | how to extend the engine |
| [docs/MECHANICS_COVERAGE.md](docs/MECHANICS_COVERAGE.md) | the full CR checklist with milestones and priorities |
| [docs/plans/standard.md](docs/plans/standard.md) | progress: what's done, what's in progress, what's pending, and the per-set gap census |
| [docs/DESIGN.md](docs/DESIGN.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | design decisions and code layout |

## Development

```sh
bundle exec rake            # specs (with coverage gate + docs drift check) and RuboCop
bundle exec rake docs       # regenerate SUPPORTED.md and docs/reference after changing a primitive
bundle exec rake fuzz[50,1] # 50 random games, invariants checked after every decision
bundle exec rake bench      # games per second (benchmark-ips)
bundle exec rake profile    # stackprof CPU profile
```

Every mechanic is tested at three levels:
- **Unit:** the primitive and its validation.
- **Integration:** scenario boards built with a small DSL, then legal options, then a decision, then the resulting state and events.
- **End-to-end:** full 60-card games, scripted and fuzzed, with export/import round-trips.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), then
[adding a mechanic](docs/guides/adding-a-mechanic.md), and pick a ★ item that's
in current Standard from the [coverage checklist](docs/MECHANICS_COVERAGE.md).
Bugs and rules questions go to
[GitHub issues](https://github.com/thisiscetin/enjine/issues). When something
behaves differently from the Comprehensive Rules, include the seed and the
decision log (or a saved snapshot).

## License

MIT. Magic: The Gathering is a trademark of Wizards of the Coast. Enjine is an
unofficial fan project, not affiliated with or endorsed by Wizards of the Coast.
Card names in the sample pool are used for illustration only.
