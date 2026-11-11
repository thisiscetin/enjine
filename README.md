# Enjine

**A deterministic, rules-accurate Magic: The Gathering engine for Ruby, built for the Standard format.**

Enjine runs two-player Magic: The Gathering games by the
[Comprehensive Rules](https://magic.wizards.com/en/rules) (pinned to the version
effective **2026-11-06**). It turns every moment of the game into an explicit,
atomic decision with a list of legal options. That makes it a solid base for
simulations, bots and reinforcement learning, or for a game client.

**Scope: Standard.** Enjine implements the core rules and the mechanics of the
current Standard-legal sets. Mechanics found only outside Standard (morph,
madness, infect, ...) are out of scope until a Standard card needs them. The
[mechanics coverage](docs/MECHANICS_COVERAGE.md) page has the details and the
numbers.

- **Strict rules.** Turn structure, priority, the stack, layers, replacement
  effects, combat, state-based actions, London mulligan. Code and tests cite rule
  numbers.
- **Cards are data.** You write each card as a JSON block in the
  [card DSL](docs/guides/card-data-format.md); Enjine validates it and never
  reads card text. Unknown mechanics are rejected with path-addressed errors.
- **Atomic decisions.** One small choice at a time (cast → target → tap → pay),
  each one cancellable until the costs are paid.
- **Deterministic.** Seeded PCG32 RNG: the same seed and decisions give the same
  game, bit for bit. Export or import any moment, even mid-cast.
- **Hidden information handled properly.** Per-player views and histories, plus an
  omniscient observer view.
- **No runtime dependencies.** Plain Ruby 4.0.

> **Status: 0.1, pre-release.** Progress and what's pending are in
> [docs/plans/standard.md](docs/plans/standard.md).

## Set support

Enjine ships no card data. These are the Standard sets and the card types for
which real cards are written in the DSL and tested
(`spec/fixtures/cards/real/`, each card with a scenario spec and rules-monitored
play):

| Set | Creature | Instant | Sorcery | Artifact | Enchantment | Land | Planeswalker | Battle | Kindred |
|---|---|---|---|---|---|---|---|---|---|
| Star Trek (`trk`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Reality Fracture (`fra`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a |
| The Hobbit (`hob`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Marvel Super Heroes (`msh`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Secrets of Strixhaven (`sos`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a |
| Teenage Mutant Ninja Turtles (`tmt`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Lorwyn Eclipsed (`ecl`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | ✓ |
| Avatar: The Last Airbender (`tla`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Spider-Man (`spm`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Edge of Eternities (`eoe`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a |
| Final Fantasy (`fin`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a | n/a |
| Tarkir: Dragonstorm (`tdm`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | n/a | n/a |
| Aetherdrift (`dft`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a |
| Foundations (`fdn`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | n/a | n/a |

✓: at least one real card of that type from that set is written and tested.
—: none yet. n/a: the set has no card of that type. Known gaps are listed per
set in [docs/plans/standard.md](docs/plans/standard.md#mechanics-gaps).

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
    "effects": [{ "deal_damage": { "amount": 3, "to": { "target": 0 } } }] } }],
  "rarity": "common", "printing": { "set": "fdn", "number": "1" } }
```

`rarity` and `printing` are optional and ignored by the rules. Check your cards:

```sh
bundle exec exe/enjine --validate cards.json   # JSON report; exit 1 if any card is invalid
bundle exec exe/enjine --verify my_cards/      # validate, then play-test them in rules-monitored games
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
| [docs/MECHANICS_COVERAGE.md](docs/MECHANICS_COVERAGE.md) | scope and coverage against the Comprehensive Rules, and the full CR checklist |
| [docs/plans/standard.md](docs/plans/standard.md) | progress: what's done, what's in progress, what's pending, and the per-set gap census |
| [docs/DESIGN.md](docs/DESIGN.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | design decisions, code layout and where things are |

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

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[code of conduct](CODE_OF_CONDUCT.md). Report rules bugs in
[GitHub issues](https://github.com/thisiscetin/enjine/issues) with the seed and
the decision log (or a saved snapshot). Security issues: [SECURITY.md](SECURITY.md).

## License

MIT, see [LICENSE.txt](LICENSE.txt). Changes are in [CHANGELOG.md](CHANGELOG.md).

Enjine is unofficial Fan Content, not approved or endorsed by Wizards of the
Coast. Magic: The Gathering, card names and the Comprehensive Rules are property
of Wizards of the Coast LLC. The repository contains no card text, art or rules
text: test cards are structured data written by hand, and only rule numbers are
cited.
