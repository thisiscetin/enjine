# Enjine — Design

Enjine is a Ruby gem that runs two-player Magic: The Gathering games with strict
Comprehensive Rules (CR) fidelity. It is pure gameplay infrastructure: no AI, no
heuristics, no "smartness". Callers (a text CLI today, reinforcement-learning
agents in a separate project later) drive it through an atomic decision API.

## 1. Scope

- Two-player constructed: 20 life, deck ≥ 60 cards, max 4 copies of a card
  (basic lands and "any number" cards exempt). No sideboard tracking.
- Single games, start to finish. No best-of-3 / match object.
- The engine knows **no cards** by default. A curated pool ships as an opt-in
  (`require "enjine/card_pool/core"`), used by tests and seeding.
- Pinned to a dated CR version. Code and tests cite rule numbers (`# CR 704.5a`).

## 2. Cards

- **Data-first.** Card definitions are pure data (JSON / Hash). No Ruby card code.
- **Primitive registry.** Abilities are composed of named primitives: effects,
  costs, targets/filters, triggers, conditions, amounts, keywords, continuous
  effects, replacements. Each primitive declares: name, parameter schema,
  description, JSON example, CR references.
- **Validation.** Loading validates against primitive schemas. Unknown/invalid
  pieces raise `InvalidCardDefinition` listing *all* errors with paths
  (`abilities[0].effect[1].deal_damage.amount`).
- **Composition for card types.** A card has a *set* of types; each type is a
  rule module (timing, destination zone, characteristics). Keywords are modules.
  Inheritance only for engine abstractions (`Ability`, `Effect`, `Cost`,
  `Decision`, `Event`, `Zone`).
- **Extension.** A new mechanic = a new primitive class registered by name.
- **IDs.** Definition id = canonical slug of the unique card name
  (`"Lightning Bolt"` → `lightning_bolt`).

## 3. Players, Setup, Game

- `Player` = name + deck document (card definitions + decklist). `ready?` only
  when the deck is valid. Between games the deck can be edited freely
  (swap/add/remove, any number of cards) and is re-validated. Editing while
  seated in an unfinished game raises `DeckLocked`.
- `Setup` = frozen, compiled once from two ready players: validated catalog
  (union of both players' definitions; differing definitions under the same
  name → `CatalogConflict`), compiled decks. All games spawned from a Setup
  share compiled definitions in memory.
  - `setup.new_game(seed:)` — cheap new game (new shuffle, die roll, mulligans).
  - `game.restart(seed: nil)` — back to the opening; same seed = identical game.
  - `Setup + seed` fully reproduces a game; training stores seeds, not states.
- The engine runs setup itself: shuffle, die roll, play/draw choice, London
  mulligan, opening hands.

## 4. Decision API

- `game.pending_decision` → `{player, kind, options}`; `game.submit(option)`.
- **No auto-skip.** Every priority point is an explicit decision.
- **Atomic.** Each decision is one small choice: cast/activate, choose target,
  tap a mana source (manual mana — one source at a time), declare attackers,
  declare blockers, order/assign damage, choose X, choose mode, mulligan, etc.
- **Cancel** is allowed until all costs are paid; it rolls back everything done
  during that cast/activation (card back to hand, sources tapped during the
  payment untap; mana that was in the pool before stays). Once costs are paid
  the spell is cast and cannot be undone.
- Invalid submission raises `IllegalDecision` (with the legal options); state is
  never partially mutated.

## 5. State, Events, History, Views

- Mutable state of compact structs indexed by id; seeded RNG; fully deterministic.
- **Object ids**: `<definition_id>#<n>` from a per-game counter. A new id on every
  zone change (CR 400.7).
- **Events**: every change is a typed, serializable event (`DamageDealt`,
  `ZoneChanged`, `LifeChanged`, `CounterAdded`, `StepBegan`, ...). Events drive
  triggers, history, the CLI log and test assertions.
- **History**: ordered log of (turn, step, player, decision, resulting events).
  `history_for(player)` hides what that player cannot know; the observer history
  shows everything.
- **Views**:
  - `view_for(player)` — that player's legal knowledge (opponent hand and
    libraries as counts).
  - `view_for(:observer)` — omniscient: hands, face-down cards, library order.
  - `state` — raw internals, for tests/debugging.

## 6. Export / Import / Fast-forward

- JSON snapshot: full state, RNG state, pending decision; versioned schema.
- Replay: seed + decision log.
- `game.apply([decisions])` and snapshot import are **transactional**: all or
  nothing; on failure the game is restored and the error names the failing
  index and reason.
- Deck rules apply to new games only; an imported state must be internally
  consistent (valid zones, real objects, legal step, matching pending decision).

## 7. Errors

`Enjine::Error` → `IllegalDecision`, `InvalidCardDefinition`, `InvalidDeck`,
`InvalidSnapshot`, `CatalogConflict`, `DeckLocked`.

## 8. Testing

Every mechanic ships with three levels:

1. **Unit** — the primitive in isolation (schema, validation, effect on a
   minimal state).
2. **Integration** — scenario builder imports a board position, asserts legal
   options, submits a decision, asserts resulting state and events.
3. **End-to-end** — full games from two 60-card decks via `Setup`, scripted and
   fuzzed (random legal options), with invariant checks after every step.

RSpec. CI (GitHub Actions): RSpec, RuboCop, SimpleCov ≥ 95% line + branch,
docs drift check, short fuzz run.

## 9. Docs

- Generated from the primitive registry: `docs/reference/*.md`, `SUPPORTED.md`.
  CI fails on drift.
- Hand-written guides in `docs/guides/`: game lifecycle, decision API, card data
  format, adding a mechanic.

## 10. Tooling & Performance

- Ruby 4.0.x with YJIT. Zero runtime dependencies.
- Dev: rspec, rubocop(-rspec), simplecov, benchmark-ips, stackprof,
  memory_profiler. Benchmarks/profiling are rake tasks, not CI gates.
- `exe/enjine`: text CLI, random decks from the pool, seats `human` / `random`.

## 11. Milestones

1. **Skeleton** — setup, zones, turn structure, priority, mulligan, lands, manual
   mana, vanilla creatures, combat, SBAs, win/lose, export/import, CLI, fuzzer.
2. **Stack** — instants/sorceries, targeting, countering, activated & triggered
   abilities, cancel.
3. **Continuous effects** — layers (CR 613), static abilities,
   replacement/prevention, counters, auras, equipment.
4. **Keywords & planeswalkers**.
5. **Long tail** — copy, control change, exotic mechanics, larger pool.
