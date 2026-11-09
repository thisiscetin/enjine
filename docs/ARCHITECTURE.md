# Enjine — Architecture

Companion to [DESIGN.md](DESIGN.md). Describes how the code is laid out and why.
Rules reference: Comprehensive Rules effective **2026-11-06**.

## Folder structure

```
lib/enjine.rb                     # entry point; requires everything except card pools
lib/enjine/
  version.rb                      # VERSION, RULES_VERSION (pinned CR date)
  errors.rb                       # Error hierarchy
  rng.rb                          # PCG32, integer state -> JSON-exportable, deterministic
  mana.rb                         # mana costs, symbols, pools

  # ---- static world: cards & decks (no game state) ----
  primitive.rb                    # Primitive base class + Registry (every mechanic registers here)
  mechanics.rb                    # helpers to build primitives from data entries
  card_definition.rb              # immutable, validated blueprint built from a data Hash
  catalog.rb                      # id -> CardDefinition, conflict detection
  deck.rb  player.rb  setup.rb    # decklists, players, compiled pairings

  mechanics/                      # ONE PLACE PER MECHANIC: <category>/<mechanic>.rb, all registered primitives
    types/ supertypes/ subtypes/  card types, supertypes, subtypes (permanent_types spell_types land saga auras_and_equipment ...)
    keywords/                     keyword abilities, CR 702 (evergreen flags crew kicker ward station alternative_costs ...)
    abilities/                    other abilities: stack_abilities (spell activated triggered loyalty), static, mana_ability,
                                  replacement_effects, play_permissions, cost_changes, enters_tapped ...
    triggers/                     trigger events grouped by what happens (zone_changes combat casting life ...)
    costs/ effects/ filters/ counters/   one file per cost, effect (damage exile counters library ...), filter, counter kind
    */base.rb                     shared bases of effects, triggers, filters, costs (abilities: stack_abilities.rb),
                                  loaded first; a file requires any other mechanic it extends
    selector.rb values.rb         who an effect applies to (target / self / you / each ...); amounts and conditions
    linked.rb card_spec.rb ...    shared helpers: linked abilities, token/copy card specs, mana spent

  # ---- dynamic world: a running game ----
  game.rb                         # public facade: pending_decision / submit / apply / export / views
  state.rb                        # State, PlayerState, GameObject (plain mutable structs)
  engine.rb                       # the state machine: accessors, emit, options/submit!; one module per area below
  engine/
    pregame.rb priority.rb        # CR 103 start and mulligans; CR 117 priority
    turn_structure.rb             # CR 500-502: advance!, steps, untap step, land plays
    zones.rb                      # CR 400: create/move objects (through replacements), tokens, draw, tap
    casting/                      # CR 601/602: casting.rb (announce, targets, cancel/rewind), payment.rb,
                                  #   cast_choices.rb, costs.rb, target_counts.rb, alt_casting.rb, permissions.rb
    mana_sources.rb               # CR 106/605: affordability, mana abilities, mana pools
    resolution.rb entering.rb     # CR 608: resolve top of stack, fizzle; "as this enters" choices
    triggers.rb                   # CR 603: matching events, pending triggers
    combat.rb                     # CR 506-511: attackers, blockers, damage assignment
    damage.rb                     # damage, life, counters
    state_based_actions.rb        # CR 704 and game end (CR 104)
    characteristics.rb            # CR 613 layer pipeline for P/T, continuous effects, cleanup
    rules.rb copies.rb faces.rb ...   # player rules and control; copies (CR 707); faces; sagas, phasing, speed ...
  steps.rb                        # 12 step objects with turn-based actions
  events.rb                       # typed, serializable events + per-viewer redaction
  decisions/                      # one class per decision kind
    priority play_or_draw mulligan bottom discard casting(choose_target, pay_cost) combat(...)
  actions/                        # options offered at priority
    pass play_land activate_mana_ability cast(cast, activate)
  snapshot.rb                     # export/import + full consistency validation (also the fuzz invariant)
  view.rb  history.rb             # per-viewer views and histories

  # ---- tooling (no game logic) ----
  docs.rb                         # generates docs/reference/*.md + SUPPORTED.md from the Registry
  agents/random.rb  fuzz.rb       # random legal player, invariant-checking fuzzer
  cli.rb  cli/text.rb             # interactive hot-seat CLI + text renderer, --validate
  deck_builder.rb                 # OPT-IN random constructed decks from a card pool
exe/enjine
examples/                         # ready-to-play decks and a card pool (not in the gem)
spec/ unit/ integration/ e2e/ support/scenario.rb  fixtures/cards/ (the test and fuzz cards)
docs/ DESIGN.md ARCHITECTURE.md MECHANICS_COVERAGE.md SUPPORTED.md(root) reference/ guides/
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

### 6a. Cards outside the game
A game doesn't know about a match, so a deck's optional `outside` list stands for the
cards its player owns outside the game (a constructed sideboard, CR 400.11a, 100.4a).
At setup each player gets `PlayerState#outside`, a list of definition ids. These are not
objects, because outside the game isn't a zone and the cards have no ids yet
(CR 400.11). `State#outside_lists` keeps the starting lists for `restart`. Both
round-trip through snapshots, which check every id against the catalog. Legal actions
name such a card `outside:<card id>`, and legality checks use a detached stand-in
object that is never stored. The real object is created only as the card enters
the stack or the battlefield (`Engine#bring_in_from_outside!`), owned by that player
(CR 108.3). A cancelled cast puts the id back in the list.

### 7. Atomicity
`submit` validates against the legal options before touching anything. `apply`
and `import` work on a Marshal copy and swap it in only on success. Events are
buffered and delivered to subscribers only after success.
