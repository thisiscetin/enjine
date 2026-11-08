# Enjine

**A deterministic, rules-accurate Magic: The Gathering game engine for Ruby.**

Enjine runs two-player Magic: The Gathering games by the
[Comprehensive Rules](https://magic.wizards.com/en/rules) (pinned to the version
effective **2026-09-25**). It turns every moment of the game into an explicit,
atomic decision with a list of legal options. That makes it a solid base for
simulations, bots and reinforcement learning, or for a game client.

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

> Status: early (0.1). The core game loop, creatures, instants, sorceries,
> planeswalkers, activated and loyalty abilities, combat, counters and
> until-end-of-turn effects work. Many keywords and rules areas are still to come.
> See [`SUPPORTED.md`](SUPPORTED.md) (generated from the code) and the
> [mechanics coverage checklist](docs/MECHANICS_COVERAGE.md).

## Try it: play both sides in your terminal

```sh
git clone https://github.com/<you>/enjine && cd enjine
bundle install
bundle exec exe/enjine                     # hot-seat: you play both players
bundle exec exe/enjine --list-decks        # sample decks
bundle exec exe/enjine --deck1 izzet_spells --deck2 gruul_beats --seed 7
bundle exec exe/enjine --p2 random         # play against a random opponent
```

```
━━ Turn 3 · Main 1 · active: alice · priority: alice ━━━━━━━━━━━━━━━━━━━━━━━━━
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

▶ ALICE must act: priority
   1) Pass priority
   2) Cast Lightning Bolt {R}
   3) Tap Mountain for mana ({T}: Add {R}.)
   …
alice> 2
```

Commands: a number picks an option, `f` fast-forwards through priority passes,
`o` toggles the observer view (both hands and library order), `h` shows the
history, `u` undoes, `s FILE` saves, `--load FILE` resumes, and `?` shows help.

## Use it as a library

```ruby
require "enjine"
require "enjine/card_pool/core"   # opt-in sample cards; Enjine knows no cards by default

alice = Enjine::Player.new(name: "alice", deck: Enjine::CardPool::Core.deck("gruul_beats"))
bob   = Enjine::Player.new(name: "bob",   deck: Enjine::CardPool::Core.deck("azorius_walkers"))
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

More in [docs/guides/decision-api.md](docs/guides/decision-api.md).

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

Validate cards in bulk, for example from a Scryfall import pipeline:

```sh
bundle exec exe/enjine --validate cards.json   # JSON report, exit code 1 if any card is invalid
```

The [card data format guide](docs/guides/card-data-format.md) is written so you
can hand it to an agent that converts a card database into Enjine format.

## Documentation

| Document | What it covers |
| --- | --- |
| [SUPPORTED.md](SUPPORTED.md) | every supported type, keyword, ability, cost, effect and filter (generated) |
| [docs/reference/](docs/reference) | parameters and examples for every primitive and decision (generated) |
| [docs/guides/card-data-format.md](docs/guides/card-data-format.md) | the card data format, Scryfall mapping, validation, DB schema |
| [docs/guides/decision-api.md](docs/guides/decision-api.md) | playing a game through the API |
| [docs/guides/adding-a-mechanic.md](docs/guides/adding-a-mechanic.md) | how to extend the engine |
| [docs/MECHANICS_COVERAGE.md](docs/MECHANICS_COVERAGE.md) | the full CR checklist with milestones and priorities |
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

Contributions are welcome. Start with
[adding a mechanic](docs/guides/adding-a-mechanic.md) and pick a ★ item from the
coverage checklist.

## License

MIT. Magic: The Gathering is a trademark of Wizards of the Coast. Enjine is an
unofficial fan project, not affiliated with or endorsed by Wizards of the Coast.
Card names in the sample pool are used for illustration only.
