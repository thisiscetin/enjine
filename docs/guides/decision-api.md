# The decision API

Every game advances one atomic decision at a time. There is no auto-pass and no
hidden logic. The engine asks, you answer.

```ruby
require "enjine"

# A deck document carries the cards it uses (see examples/decks in the repository).
alice = Enjine::Player.new(name: "alice", deck: JSON.parse(File.read("examples/decks/gruul_beats.json")))
bob   = Enjine::Player.new(name: "bob",   deck: JSON.parse(File.read("examples/decks/azorius_walkers.json")))
setup = Enjine::Setup.new(alice, bob)   # validated and compiled once
game  = setup.new_game(seed: 42)        # cheap; one per game

until game.over?
  decision = game.pending_decision      # Decision(player:, kind:, options:, details:)
  game.submit(decision.options.sample)  # your agent decides here
end
game.result  # => {"winner" => "bob", "reason" => "life"}
```

## Decisions

`game.pending_decision` returns:

| Field | Meaning |
| --- | --- |
| `player` | name of the player who must decide |
| `kind` | `play_or_draw`, `mulligan`, `bottom`, `priority`, `choose_target`, `pay_cost`, `declare_attackers`, `declare_blockers`, `assign_damage`, `discard` |
| `options` | every legal answer, as hashes like `{type: "cast", object: "lightning_bolt#12"}` |
| `details` | extra context, e.g. `{"remaining" => "{1}{G}"}` while paying |

Submit any option exactly as listed; string keys from JSON also work. An illegal
option raises `Enjine::IllegalDecision` (with `legal_options`) and changes nothing.
The full catalog of kinds and option types is generated in
[`docs/reference/decisions.md`](../reference/decisions.md).

### Casting is several decisions

Casting Lightning Bolt with a Mountain on the battlefield:

```ruby
game.submit(type: "cast", object: "lightning_bolt#12")                # priority -> card moves to the stack
game.submit(type: "target", target: "player:bob")                     # choose_target
game.submit(type: "activate_mana", object: "mountain#3", ability: "intrinsic:mountain")  # pay_cost: tap a source
game.submit(type: "pay_mana", mana: "R")                              # pay_cost: spend {R} -> cast
```

At any point before the last payment, `{type: "cancel"}` rewinds the whole cast:
the card returns to the same place in hand, sources tapped during the cast untap,
and the mana pool is restored (CR 734).

## Observing

| Call | Returns |
| --- | --- |
| `game.view_for("alice")` | what Alice may know: her hand, public zones, and counts of hidden zones |
| `game.view_for(:observer)` | everything, including both hands and library order |
| `game.history_for("alice")` | every decision and its events; hidden details redacted for Alice |
| `game.subscribe { \|event\| }` | typed events as they happen (`Enjine::Events::*`) |
| `game.state` | the raw internal state (tests and debugging) |

Views include computed characteristics: creature `power`/`toughness` after
counters and effects, `damage`, `summoning_sick`, `attacking`/`blocking`, and
planeswalker `loyalty`.

## Time travel

| Call | Effect |
| --- | --- |
| `game.export` / `Game.import(json, catalog:)` | snapshot at any decision, including mid-cast |
| `game.apply([...options])` | fast-forward; all or nothing, and the error names the failing index |
| `game.decision_log` + seed | `setup.new_game(seed:).apply(log)` replays the game exactly |
| `game.restart(seed: nil)` | back to the opening; the same seed gives an identical game |
| `game.concede("alice")` | CR 104.3a |
