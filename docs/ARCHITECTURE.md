# Enjine — Architecture

Companion to [DESIGN.md](DESIGN.md). Describes how the code is laid out and why.
Rules reference: Comprehensive Rules effective **2026-09-25**.

## Folder structure

```
lib/enjine.rb                     # entry point; requires everything except card pools
lib/enjine/
  version.rb
  errors.rb                       # Error hierarchy
  rng.rb                          # PCG32, integer state -> JSON-exportable, deterministic
  mana.rb                         # ManaCost parsing, colors, mana symbols

  # ---- static world: cards & decks (no game state) ----
  primitive.rb                    # Primitive base class + Registry (every mechanic registers here)
  card_definition.rb              # immutable, validated blueprint built from a data Hash
  catalog.rb                      # id -> CardDefinition, conflict detection
  deck.rb                         # decklist + its card definitions, validation, edit ops
  player.rb                       # name + deck, ready?, DeckLocked while seated
  setup.rb                        # frozen, compiled once from 2 players -> new_game(seed:)

  mechanics/                      # ONE FILE PER MECHANIC, all registered primitives
    types/land.rb                 #   card types (composition modules)
    supertypes/basic.rb
    subtypes/basic_land_types.rb  #   Plains/Island/... intrinsic mana abilities (CR 305.6)
    abilities/mana_ability.rb     #   activated mana abilities (CR 605)
    costs/tap.rb                  #   {T}

  # ---- dynamic world: a running game ----
  game.rb                         # public facade: pending_decision / submit / apply / export / views
  state.rb                        # State, PlayerState, GameObject (plain mutable structs)
  engine.rb                       # the state machine: advance!, zone moves, SBAs, turn flow
  steps.rb                        # 12 step objects (untap .. cleanup) with turn-based actions
  events.rb                       # typed, serializable events + per-viewer redaction
  decisions/                      # one class per decision kind (pending decision types)
    priority.rb  play_or_draw.rb  mulligan.rb  bottom.rb  discard.rb
  actions/                        # options offered at priority (extensible list)
    pass.rb  play_land.rb  activate_mana_ability.rb
  snapshot.rb                     # export/import + full consistency validation (also the fuzz invariant)
  view.rb                         # view_for(player | :observer)
  history.rb                      # decision log + events, per-viewer filtering

  # ---- tooling (no game logic) ----
  docs.rb                         # generates docs/reference/*.md + SUPPORTED.md from the Registry
  agents/random.rb                # picks uniformly among legal options (fuzzing / CLI seat)
  fuzz.rb                         # plays N random games, checks invariants + export/import roundtrip
  cli.rb                          # text UI
  card_pool/core.rb               # OPT-IN: require "enjine/card_pool/core"
  card_pool/core.json
  card_pool/deck_builder.rb
exe/enjine                        # CLI executable
spec/
  unit/                           # one primitive / class in isolation
  integration/                    # scenario-builder board positions -> options -> outcome
  e2e/                            # full 60-card games from Setup, scripted + fuzzed
  support/scenario.rb             # scenario DSL -> snapshot hash -> Game.import
  docs_spec.rb                    # fails if generated docs drift
docs/
  DESIGN.md  ARCHITECTURE.md  SUPPORTED.md (generated)
  reference/*.md (generated)  guides/*.md
```

## Key design decisions

### 1. Two worlds: static vs dynamic
- **Static** (`CardDefinition`, `Catalog`, `Deck`, `Player`, `Setup`) is validated
  once and frozen. Shared by every game spawned from a `Setup` — no per-game cost.
- **Dynamic** (`State`, `GameObject`, ...) is plain mutable data. Objects refer to
  definitions **by id** (`"forest"`), never by Ruby reference, so state is small,
  Marshal-copyable, and serializable.

### 2. The engine is an explicit state machine
No Ruby call stack ever holds game progress. Turn, step, priority holder, pass
count, stack and the pending decision are fields on `State`. `submit(option)`
mutates the state one tick and `Engine#advance!` runs forward until the next
decision is needed. This is what makes export (including the pending decision),
import, transactional `apply`, `restart`, and replay possible.

### 3. Mechanics are registered primitives (composition, not inheritance)
```
Primitive (base: name, category, description, rules[], params, example, validate/build)
 ├─ category :type       -> Mechanics::Types::Land, (Creature, Instant, ... later)
 ├─ category :supertype  -> Basic
 ├─ category :subtype    -> Plains/Island/Swamp/Mountain/Forest
 ├─ category :ability    -> ManaAbility (Triggered, Static, Activated ... later)
 ├─ category :cost       -> Tap (Mana, Sacrifice ... later)
 └─ category :effect     -> (DealDamage, AddCounters ... milestone 2)
```
A card is a *set* of type primitives plus a list of ability primitives. A card
data block naming anything not in the Registry fails with
`InvalidCardDefinition` and a full list of path-addressed errors. Docs and
`SUPPORTED.md` are generated from the same Registry, so they cannot drift.

### 4. Decisions and actions are small classes with one job each
- `Decisions::*`: a kind of pending decision (`priority`, `mulligan`, `bottom`,
  `discard`, `play_or_draw`). Each one has `options(engine, pending)` and
  `submit(engine, pending, option)`.
- `Actions::*`: what you can do at priority (`pass`, `play_land`,
  `activate_mana`, and later `cast` / `activate`). Priority options are the union
  of every registered action's options. Adding casting means adding one Action class.
- Options are plain frozen hashes (`{type: "play_land", object: "forest#12"}`), so
  they are JSON-able and comparable with `==`.

### 5. Events are the single source of change
Every mutation emits a typed event (`Data` classes). Events feed history, the CLI
log, subscribers and test assertions, and triggered abilities later. Each event
knows how to redact itself for a viewer: a library→hand move shows only "drew
a card" to the opponent.

### 6. Determinism and IDs
- PCG32 RNG, with its state stored as an integer in the snapshot.
- Object id = `<definition_id>#<n>` from a per-game counter. A card gets a new id
  on every zone change (CR 400.7).
- `Setup` + seed reproduces a game exactly, and `restart` uses the same path.

### 7. Atomicity
`submit` validates against the legal options before touching anything. `apply`
and `import` work on a Marshal copy and swap it in only on success. Events are
buffered and delivered to subscribers only after success.
