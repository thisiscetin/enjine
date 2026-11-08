# Enjine review: elegance and code design

Reviewed against `docs/DESIGN.md` and `docs/ARCHITECTURE.md`. Baseline: `bundle exec rspec` gives 171 examples,
0 failures, 98.8% line and 90.2% branch coverage. Probe scripts ran outside the repo. Timings were taken on Ruby
4.0.1 **without** YJIT, so the absolute numbers are pessimistic, but the ratios hold.

## 1. Verdict

**Score: 7/10.** The skeleton is good and it matches its docs unusually well. The explicit state machine
(`Engine#advance!` plus `step_state`), the per-kind `Decisions` classes, `Steps::ORDER`, the `Events.define`
registry with per-viewer redaction, and the snapshot validator that also serves as the fuzz invariant are all small
and easy to read, and a newcomer can follow one decision from end to end in a few minutes. The weak spots are where
the composition story stops at the data boundary. Card types, keywords and costs are "registered primitives" when
they are validated, but the engine still makes them work with `creature?`, `kind ==`, `reject(&:mana?)` and string
switches. Underneath that is an informal mix of Structs, string-keyed hashes, symbol-keyed options and three ways to
name a player. I found two real bugs, both with short reproductions, and one leaky lookup that costs about 3.7x
throughput. All three are cheap to fix.

## 2. Findings

### E1. `Game#apply` on a freshly imported game raises `NoMethodError` instead of `IllegalDecision`
**Severity:** high (bug)
**Where:** `lib/enjine/game.rb:54-60` (`initialize` never sets `@version`), `lib/enjine/game.rb:148` (`record` uses `@version.to_i + 1`), `lib/enjine/game.rb:169` (`transaction` rescue uses `@version += 1`)
**Problem:** `@version` stays `nil` until the first `record`. Games created by `Game.start` reach `record` through
`start!`. Imported games (every scenario-built integration game, and every `Setup#import`) do not. If the first call
after an import is an `apply` whose first option is illegal, the rescue in `transaction` evaluates `nil + 1` and
replaces the documented `IllegalDecision` (with `index`) with a `NoMethodError`. The specs miss this because
`transactions_spec.rb:39` fails at index 2, after two successful submits have already set `@version`.

Reproduction:
```ruby
setup = Enjine::Setup.new(Enjine::Player.new(name: "a", deck: Enjine::CardPool::Core.deck("gruul_beats")),
                          Enjine::Player.new(name: "b", deck: Enjine::CardPool::Core.deck("izzet_spells")))
g = Enjine::Game.import(setup.new_game(seed: 3).export, catalog: setup.catalog)
g.apply([{ type: "bogus" }])   # => NoMethodError: undefined method '+' for nil
```
The memo itself (`@pending_for != @version`, lines 78-79) is harder to follow than it needs to be.
**Recommendation:** Set `@version = 0` in `Game#initialize`. Better still, drop the version counter: set
`@pending_decision = nil` at the start of `record`, in the `transaction` rescue after restoring state, and in
`restart`, and let `pending_decision` be `@pending_decision ||= build_decision`. Add a spec to
`spec/integration/transactions_spec.rb` that builds a game with `build_game`, calls `apply([{ type: "bogus" }])`
first, and expects `IllegalDecision` with `index == 0`.
**Effort:** S

### E2. `history_for(opponent)` crashes after a concession
**Severity:** high (bug)
**Where:** `lib/enjine/game.rb:118` (records kind `"concede"`), `lib/enjine/history.rb:17-21` (`Decisions.fetch(kind).redact`)
**Problem:** `concede` is recorded as a history entry with `kind: "concede"`, but `"concede"` is not a registered
decision kind. When the viewer is not the conceding player, `HistoryEntry#for_viewer` calls
`Decisions.fetch("concede")`, which raises. The CLI's history command, and any RL client that reads the opponent's
history of a conceded game, will crash. `decision_log` (`game.rb:135`) also special-cases `"concede"`, which shows
that concede is a pseudo-decision living outside the model.

Reproduction:
```ruby
g = setup.new_game(seed: 1)
g.concede("a")
g.history_for("b")  # => ArgumentError: unknown decision kind "concede"
```
**Recommendation:** Do **not** register `"concede"` in `Decisions::KINDS`, because `Snapshot.validate_pending`
(`snapshot.rb:224`) uses `KINDS.key?` to accept pending kinds and would then accept `pending: {kind: "concede"}`.
Instead, add `Decisions.redact(kind, option, viewer_is_decider)`. It should return `option` when `kind` is not in
`KINDS` and delegate to the class otherwise. Call it from `HistoryEntry#for_viewer`. Add an integration spec that
concedes and then reads `history_for` for both players and `:observer`.
**Effort:** S

### E3. `Catalog#fetch` re-slugs on every lookup, so the hottest call in the engine is a Unicode normalization
**Severity:** high (performance, leaky abstraction)
**Where:** `lib/enjine/catalog.rb:34-36`, `lib/enjine/card_definition.rb:19-21`, called through `Engine#definition` (`engine.rb:27`)
**Problem:** `Engine#definition(obj)` calls `catalog.fetch(obj.card)`. `obj.card` is already a canonical id, yet
`fetch` runs `CardDefinition.slug` on it every time: `unicode_normalize(:nfkd)`, then four `gsub`/`delete` passes.
Every filter check, power/toughness read, mana-source scan and option enumeration goes through this path. Measured
cost: **1272 ns per `fetch` against 52 ns for a plain Hash fetch**. In 20 random games (29,936 decisions), CPU
samples were **87% GC**, mostly from slug garbage. Making `fetch` try the id first cut the time from **117 µs to
32 µs per decision (3.7x)**. The design problem is that `fetch` quietly accepts card *names* where the engine means
*ids*, so the boundary between "user-facing name lookup" and "internal id lookup" is blurred.
**Recommendation:** Make `Catalog#fetch(id)` a plain `@definitions.fetch(id) { raise KeyError, ... }`. Keep slugging
only at the user-facing boundary: `add`, `[]`, `include?`, and a new `Catalog#find_by_name(name)` (used by the CLI,
`scenario.rb` and `CardPool::Core.deck`). Snapshot validation (`snapshot.rb:132`) should check
`catalog.include?` on the exact id. Optionally, cache the definition on a per-engine `Hash` keyed by `obj.card`.
**Effort:** S

### E4. Composition is promised for types and keywords, but the engine hardcodes them
**Severity:** medium
**Where:** `lib/enjine/engine/damage.rb:22-23,58-60`, `lib/enjine/engine/combat.rb:22,31,58`, `lib/enjine/engine.rb:273-276` (`keyword?(:haste)`), `lib/enjine/card_definition.rb:69` (`keyword?(:flash)`), `:91-92`, `lib/enjine/mechanics/effects/effects.rb:119`, `lib/enjine/view.rb:64,69`, `lib/enjine/mechanics/keywords/basic.rb` (marker classes), `lib/enjine/mechanics/types/base.rb:10,18`, `lib/enjine/mechanics/types/land.rb:16` (`playable_as_land?`, which nothing calls)
**Problem:** DESIGN section 2 says "each type is a rule module (timing, destination zone, characteristics). Keywords
are modules." In practice, a type module carries only `validate` plus three flags, and one of those flags
(`playable_as_land?`) is dead code. Creature rules (damage marking, lethal-damage SBA, attacking, blocking,
summoning sickness) and planeswalker rules (damage removes loyalty, the 0-loyalty SBA, being an attack target) are
`if defn.creature?` / `if defn.planeswalker?` branches spread over five engine files. `Flash` and `Haste` are empty
classes whose behavior is a `keyword?(:flash)` / `keyword?(:haste)` call inside the engine. Adding a keyword such as
vigilance, deathtouch or reach therefore means editing engine internals, not adding a primitive, which is the
opposite of "a new mechanic = a new primitive class registered by name".
**Recommendation:** Pick one of two options and make the code and docs agree.
- (a) **Recommended for the current milestone:** amend DESIGN/ARCHITECTURE to say that types carry validation plus
  timing and permanence, and that creature and planeswalker behavior is engine-intrinsic because the rules are
  intrinsic. Delete `playable_as_land?`.
- (b) For milestone 4 (keywords), add hook points, not deep abstraction. Give `Keyword` subclasses class-method
  predicates queried through `CardDefinition#keyword_modules` (for example `ignores_summoning_sickness?` for Haste
  and `grants_instant_speed?` for Flash). Replace `defn.keyword?(:haste)` with
  `defn.keyword_modules.any?(&:ignores_summoning_sickness?)`. Precompute these as frozen booleans in
  `CardDefinition#initialize` so the hot path stays a single ivar read.

Do not turn creature or planeswalker behavior into strategy objects. Branching on those types is cheap, and they are
genuinely special in the rules.
**Effort:** S for (a), M for (b)

### E5. The primitive contract is implicit: each category speaks a different duck protocol, and the schema is written twice
**Severity:** medium
**Where:** `lib/enjine/primitive.rb:17-27`, `lib/enjine/mechanics.rb:22` (`respond_to?(:scalar_params?)`), `lib/enjine/card_definition.rb:169` (`respond_to?(:intrinsic_abilities)`), `lib/enjine/mechanics/filters/filters.rb:41-44` (`build` returns the class), `lib/enjine/mechanics/costs/tap.rb:13-18` (`build` returns a singleton), `lib/enjine/mechanics/effects/effects.rb:14,81,109,155,165` (`self.keys`), compared with the `params:` metadata on each `primitive` call
**Problem:** A "primitive" is sometimes a class used through class methods (types, supertypes, subtypes, keywords,
filters), sometimes a singleton instance (`Tap::INSTANCE`), and sometimes a fresh instance (abilities, effects).
`Selector#to_s` calls `value.primitive_name` (a class method on a filter), while `CardDefinition` calls
`ability.class.primitive_name`. The methods each category must implement are never declared:
- abilities: `kind`, `mana_ability?`, `allowed_types`, `loyalty_cost`, `sorcery_speed?`
- costs: `payable?`, `pay!`, `mana?`
- types: `permanent?`, `instant_speed?`, `validate`

Optional capabilities are discovered with `respond_to?`. The parameter schema exists twice: the `params:` doc hash
feeds the generated reference, while `check_keys(params, %w[...])` / `self.keys` enforce validation, and nothing
keeps the two in sync. DESIGN says "each primitive declares ... parameter schema", but what each primitive actually
declares is a description.
**Recommendation:**
1. Give each category a tiny abstract base in `lib/enjine/mechanics/` (`Abilities::Ability`, `Costs::Cost`,
   `Types::CardType`, `Keywords::Keyword`, `Filters::Filter` already exists). Each base defines every protocol
   method with a default or a `NotImplementedError`. The abilities base gives `ManaAbility` and `StackAbility` a
   common parent, as ARCHITECTURE section 3 promises.
2. Make `params:` the single source of truth. Accept `params: { "amount" => { type: :integer, min: 0, doc: "..." },
   ... }` plus `scalar: true` for `ManaPayment`, then derive the `check_keys` allowed list from `params.keys` inside
   `Mechanics.build_entry`. Remove the per-class `self.keys` and the `respond_to?(:scalar_params?)` probe.
3. Document in `primitive.rb` that `build` returns "a frozen object that responds to the category protocol". It may
   return the class itself for parameterless primitives, but say so.
**Effort:** M

### E6. Costs are a list, but the engine handles the mana and loyalty costs outside it
**Severity:** medium
**Where:** `lib/enjine/mechanics/costs/mana.rb:30-32` (`payable?` is always true, `pay!` is a no-op), `lib/enjine/mechanics/abilities/stack_abilities.rb:45-53` (`StackAbility#mana_cost` sums them), `lib/enjine/engine/casting.rb:25-34,191-200` (`costs.reject(&:mana?)`, `ability.kind == :loyalty`, loyalty counters paid by hand), `lib/enjine/engine/casting.rb:90-91,118-123` (the `remaining` hash re-implements `Mana::Cost`)
**Problem:** The `Cost` abstraction (`payable?` / `pay!`) only works for `{T}`. The mana cost is a `Cost` whose
methods are stubs, and casting filters it out with `reject(&:mana?)` and pays it through a separate mechanism. The
loyalty cost is not a cost at all: it is an integer on `LoyaltyAbility`, plus `kind == :loyalty` branches in
`activatable?` and `pay_ability_costs!`, plus the once-per-turn rule on `GameObject#loyalty_turn`. The
remaining-to-pay bookkeeping is a `{"generic"=>n, "R"=>n}` hash that is converted back into a `Mana::Cost` only to
render it. Every new cost type (sacrifice, discard, pay life, remove counters, X) will add another `kind ==` branch.
**Recommendation:**
- Add `Mechanics::Costs::Loyalty`, with `payable?` checking `loyalty(obj) + n >= 0` and `pay!` adding or removing
  counters. Build it inside `LoyaltyAbility.build` from the integer `cost`.
- Move the once-per-turn and sorcery-timing checks into an `activation_restrictions` method on the ability that
  `activatable?` calls generically.
- Give `Mana::Cost` the payment arithmetic (`Mana::Cost#pay(type) -> Mana::Cost`, `#paid?`, `#payable_with?(type)`)
  and store `casting["remaining"]` as the cost string (`"{1}{G}"`), parsing it when needed. That keeps it
  JSON-friendly and deletes `remaining_text`.
- After that, `Engine::Casting` has one rule: the mana cost is paid interactively, and every other cost is paid by
  `cost.pay!`.
**Effort:** M

### E7. Activating a mana ability is implemented twice
**Severity:** medium
**Where:** `lib/enjine/actions/activate_mana_ability.rb:12-29` compared with `lib/enjine/engine/casting.rb:51-62` (`mana_sources`) and `:164-172` (`tap_for_payment!`)
**Problem:** The priority action lists mana abilities with a hand-rolled battlefield scan that matches
`Engine#mana_sources` line for line. Its `perform` repeats `tap_for_payment!` (`costs.each(&:pay!)` then
`add_mana!`). The only differences are the return shape (option hashes against `[id, i]` tuples) and the follow-up
step (`action_taken!` against recording the source for rollback and `continue_casting!`). When mana abilities gain
restrictions or non-tap costs, one copy will be updated and the other forgotten.
**Recommendation:** Add `Engine#activate_mana_ability!(index, id, ability_index)`, which pays the costs, adds the
mana and returns the source id. Make `ActivateManaAbility.options` map over `engine.mana_sources(index, nil)`.
`perform` calls `activate_mana_ability!` then `action_taken!`. `tap_for_payment!` calls `activate_mana_ability!`,
pushes onto `ctx["tapped"]`, then `continue_casting!`.
**Effort:** S

### E8. State mixes Structs, string-keyed hashes and symbol-keyed hashes, with three spellings of "kind"
**Severity:** medium
**Where:** `lib/enjine/state.rb:46-48` (`casting`, `combat_damage`, `effects`, `attackers` are raw Hashes), `lib/enjine/engine/casting.rb:92-94` (the 11-key `casting` hash), `lib/enjine/game.rb:16,181`, `lib/enjine/view.rb:90`, `lib/enjine/history.rb:10,23` (options use symbol keys and are re-keyed to strings at every boundary), `lib/enjine/engine/casting.rb:25,29,101,160,180,195,214` (`ability.kind` is a Symbol, `ctx["kind"]` / `obj.kind` / `pending["kind"]` are Strings)
**Problem:** `GameObject` and `PlayerState` are Structs with `to_h`. The casting context, combat-damage queue,
continuous effects and attacker records are bags of string keys that every file reads with `ctx["remaining"]`,
`cd["queue"]` and similar, so a typo fails silently with `nil`. Options are symbol-keyed and frozen, while `pending`
is string-keyed, and the two are joined in `Decision#to_h` and `View.pending_view` with `transform_keys(&:to_s)`.
Ability kinds are Symbols (`:loyalty`) and object kinds are Strings (`"ability"`). A newcomer has to remember which
convention each piece uses.
**Recommendation:**
1. Add `CastingContext = Struct.new(:player, :object, :kind, :origin, :source, :ability, :targets, :remaining,
   :pool, :tapped, keyword_init: true)` with `to_h` / `self.from_h`, and do the same for `CombatDamage`. Build them
   in `Snapshot.build` and serialize them in `State#to_h`. The JSON shape does not change, so `Snapshot::VERSION`
   stays 1.
2. Use Symbols for every *in-memory* discriminator (`obj.kind`, `casting.kind`) and convert to Strings only in
   `to_h` and `from_h`.
3. Leave the option and pending wire format alone. Document in `decisions.rb` that options are symbol-keyed in Ruby
   and string-keyed in JSON, and route the conversion through one helper (`Decisions.option_to_h`) in place of the
   four inline `transform_keys` calls.
**Effort:** M

### E9. `GameObject` is a 14-field union of "card" and "stack ability", built by hand in four places
**Severity:** medium
**Where:** `lib/enjine/state.rb:6-16`, `lib/enjine/engine.rb:210-216`, `lib/enjine/engine/casting.rb:81-85,220-227`, `lib/enjine/snapshot.rb:61-67`, `spec/support/scenario.rb` (`object_h`)
**Problem:** A stack ability is a `GameObject` with `kind: "ability"` whose `card` is the *source's* card id. As a
result, `engine.definition(ability_obj)` returns the source card's definition, so anything that iterates the stack
and asks `definition(obj).creature?` gets a misleading answer. `Filters::Filter.type?` and `Filters::Spell` each
have to remember `object.kind == "card"` to protect against this (`filters.rb:46,103`). Some fields are meaningless
for whole classes of objects: `damage`, `loyalty_turn` and `controlled_since` for abilities, and `source`, `ability`
and `targets` for permanents. Each construction site lists all 14 keywords, and `restore_to_hand!` repeats them
verbatim, so adding a field means editing four or more places.
**Recommendation:**
- Add `GameObject.card(id:, card:, owner:, zone:)` and `GameObject.ability(id:, card:, controller:, source:,
  ability:)` factories in `state.rb` that set every default, and use them in `create_object`,
  `begin_activation!`, `restore_to_hand!` and `Snapshot.build_object`.
- Add `Engine#ability_of(stack_obj)`, which returns the `Ability` primitive for either a spell or an ability on the
  stack. It replaces the four copies of `definition(obj).abilities[obj.ability]` / `spell_ability` in
  `casting.rb:24,80,101,193`, `resolution.rb:10` and `view.rb:78`.
- Make `Filters::Filter.match_object?` receive only `kind == :card` objects by filtering once in `candidates` and
  `match?`.
**Effort:** S

### E10. Continuous effects are interpreted by a string switch in the engine, not by their primitive
**Severity:** medium
**Where:** `lib/enjine/engine/characteristics.rb:20-24`, `lib/enjine/engine/characteristics.rb:32-51`, `lib/enjine/mechanics/effects/effects.rb:118-121`
**Problem:** `Pump#apply` writes a hash `{"kind"=>"pump","power"=>..}` into `state.effects`, and the layer pipeline
in `Engine::Characteristics` has `next unless effect["kind"] == "pump"`. The primitive knows how to *create* the
effect but not how it *modifies* characteristics, so that knowledge lives in the engine. Milestone 3 (layers, static
abilities, anthems, setting effects, switching) will grow this into a large `case effect["kind"]`, which is exactly
where the "one place per mechanic" rule matters most. The `Characteristics` module also owns `cleanup_turn!` (damage
removal), which is unrelated to characteristics.
**Recommendation:** Add a `continuous` registry. Each continuous-effect kind is a primitive class with `layer`
(`:"7c"` and so on) and `apply(pt, effect_hash) -> pt`. `Pump` registers `"pump"`. `power_toughness` groups
`state.effects` by layer and calls `Registry.fetch(:continuous, e["kind"]).apply`. The effect stays plain data in
`State`, so serialization is unaffected. Move `cleanup_turn!` into `Engine` (turn structure) or `Damage`. For
performance, cache `power_toughness` per object for the duration of one `options` call (invalidate on `@version`
bump). Today it recomputes over all effects for every query.
**Effort:** M

### E11. Engine is one ~70-method public surface, and rules logic leaks into some Decision classes but not others
**Severity:** medium
**Where:** `lib/enjine/engine.rb` plus five mixins (all methods public), `lib/enjine/decisions/discard.rb:17-25` (count decrement and re-ask live in the decision), `lib/enjine/decisions/combat.rb:20` (`done` calls `finish_attackers!`) compared with `:35` (`done` calls `turn_based_actions_done!` directly), `lib/enjine/decisions/bottom.rb:17-20` (delegates to `next_bottom_or_start!`)
**Problem:** Decisions, Actions, Steps and every primitive call straight into `Engine`, and nothing distinguishes the
small set of operations a primitive should use (`move!`, `deal_damage!`, `draw!`, `add_counters!`, `tap!`,
`change_life!`, `add_continuous_effect!`) from internal flow control (`ask!`, `turn_based_actions_done!`,
`continue_casting!`, `next_damage_assignment!`). Because nothing marks the boundary, decision classes are
inconsistent: `Discard` contains rules logic, `DeclareBlockers` reaches into turn flow, and `Bottom` delegates
cleanly. ARCHITECTURE says "decisions are small classes with one job", which is true, but the job differs from class
to class.
**Recommendation:**
- Make every Decision a pure adapter: options come from one engine query, and submit calls one engine command. Move
  the discard loop into `Engine#discard!(index, id)`, which asks again or finishes. Add
  `Engine#finish_blockers!` for symmetry with `finish_attackers!`.
- Add a short comment block at the top of `engine.rb` listing the "primitive API" (the mutators above plus `state`,
  `object`, `definition`, `power`, `toughness`, `loyalty`). Mark the casting and combat continuations `private` in
  their mixins. They are only called from inside `Engine`, apart from the decision entry points, which should stay
  public.
- Do not split Engine into collaborator objects. The single-object state machine is a good choice for export and
  performance.
**Effort:** S-M

### E12. A player has three identities: index, name and `"player:<name>"`
**Severity:** low
**Where:** `lib/enjine/mechanics/filters/filters.rb:11-17`, `lib/enjine/engine/combat.rb:30,35`, `lib/enjine/mechanics/selector.rb:73-86`, `lib/enjine/engine/damage.rb:11`
**Problem:** State stores players as indexes, while events and views use names. Targets and attack targets, which are
also *stored in state* (`attackers[id]["target"]`, `obj.targets`), use `"player:<name>"` strings. Each one is parsed
back with `Filters.player_index`, which runs `names.index(...)` per call. A player's name therefore leaks into the
internal state graph, so renaming or anonymizing a player for RL self-play would require rewriting the state, and the
lookup is a linear search on hot paths (`Selector#each`, `deal_damage!`).
**Recommendation:** Use `"player:0"` / `"player:1"` (index-based) internally, and translate to
`"player:<name>"` only in `View`, `Events#for_viewer` and `Game#submit` input normalization. Put `ref_for(index)`,
`index_for(ref)` and `player_ref?(ref)` in one module (`Enjine::Refs`). If the snapshot format changes, bump
`Snapshot::VERSION`.
**Effort:** M

### E13. `Game.import` hides engine bugs as `InvalidSnapshot`, and `submit` overstates its atomicity
**Severity:** low
**Where:** `lib/enjine/game.rb:37-38`, `lib/enjine/game.rb:11` (doc comment), `lib/enjine/game.rb:89-99`
**Problem:** `rescue ArgumentError, KeyError, NoMethodError, TypeError` around the whole import, including
`verify_pending!`, which runs `engine.options` (real rules code), turns any engine defect reachable from an imported
position into "malformed snapshot". The fuzzer's roundtrip check goes through this path, so a regression there would
be reported as bad input. Separately, `submit` validates the option and then mutates in place. An internal exception
partway through leaves a half-applied state, which contradicts the class doc "Every call either fully succeeds or
raises and leaves the game untouched".
**Recommendation:** Narrow the rescue to `Snapshot.load` and `HistoryEntry.from_h`, and let `verify_pending!` errors
propagate. Either change the doc to "illegal submissions never mutate state", or wrap `submit` in the existing
`transaction`, but only behind a `paranoid:` flag, because `Marshal.dump` on every decision is too slow for RL.
**Effort:** S

### E14. Object ids embed the card name, which conflicts with hidden information
**Severity:** low (design tension, not yet a bug)
**Where:** `lib/enjine/engine.rb:211` (`"#{card}##{n}"`), DESIGN section 5 "Object ids"
**Problem:** Today, ids of hidden objects never reach an opponent's view, because `ZoneChanged#for_viewer` strips
them and `Bottom.redact` drops `object`. However, every future hidden-but-referenced object (face-down cards,
"exile a card from your hand face down", revealed-then-shuffled cards, hand ids in an opponent-visible
`choose_target` candidate list) would leak its identity through its id. Every new redaction site has to remember
this.
**Recommendation:** No change before milestone 5. Record in DESIGN that "ids leak identity, never expose a hidden
object's id", and add a viewer-level assertion to the fuzzer: no string matching `/\A[a-z0-9_]+#\d+\z/` in
`view_for(p)` or `history_for(p)` refers to an object in a zone hidden from `p`. If face-down cards arrive, switch to
opaque ids (`"o#{n}"`) with `card` as a separate field. The snapshot already stores both.
**Effort:** S (assertion), L (id change)

### E15. Small duplications and inconsistencies
**Severity:** low
**Where:** `lib/enjine/snapshot.rb:233-239` and `lib/enjine/card_definition.rb:189-196` (two `deep_stringify`), `lib/enjine/state.rb:99-105` (`deep_dup`) and `lib/enjine/snapshot.rb:69` (Marshal `deep_copy`), `lib/enjine/engine/characteristics.rb:39-41` (`next_timestamp!` takes numbers from `state.next_id`), `lib/enjine/actions.rb:18` (bare `KeyError` on unknown type; `Actions` has no `Base`, unlike `Decisions`), `lib/enjine/mechanics/effects/effects.rb:65` (`ctx.source || ctx.object`, but `source` is always set)
**Problem:** These are small individually, but together they add to a newcomer's reading load. Three deep-copy or
stringify helpers do nearly the same thing. Timestamps and object ids share one counter, so adding a pump effect
shifts every later object id, which is surprising when diffing replays. `Decisions` and `Actions` are parallel
registries with different shapes.
**Recommendation:**
- Add `Enjine::Data` (or `Enjine::Util`) with `deep_stringify` and `deep_dup`, and use it everywhere. Replace the
  Marshal `deep_copy` in `Snapshot.build` with `deep_dup`, which is faster for JSON-shaped data.
- Either add `state.next_timestamp` (serialized, validated as a non-negative integer) or write a comment stating
  that the shared counter is deliberate (CR 613.7 timestamps).
- Give `Actions` a `Base` with `doc` and a friendly `fetch` error that mirrors `Decisions.fetch`.
- Drop the dead `|| ctx.object`.
**Effort:** S
