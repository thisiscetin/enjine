# Review: future-proofness and extensibility

Reviewed: `lib/enjine/**` (about 4,450 LOC), `docs/DESIGN.md`, `docs/ARCHITECTURE.md`,
`docs/MECHANICS_COVERAGE.md`, `SUPPORTED.md`, `docs/guides/card-data-format.md`.
Rules: CR effective 2026-09-25 (as pinned by the repo).
Question: will this architecture survive the rest of the Comprehensive Rules
without rewrites? Priority: mechanics on currently Standard-legal cards.

Effort scale: **S** under a day of agent work, **M** 1–3 days, **L** 1–2 weeks,
**XL** more than 2 weeks.

---

## 1. Verdict

**Score: 5 / 10 as it stands. About 8 / 10 once F1–F3 and F12 are done. All four
are cheap now (the engine is small) and expensive after M2.**

The *principles* are right. Several of the most important ones are already
built and load-bearing. But three core assumptions in the code are wrong for
everything past "vanilla spells and creatures", and every new mechanic added
on top of them makes them more expensive to fix:

1. resolution (and SBAs, mana abilities, combat damage) runs synchronously in
   Ruby and can't stop for a decision (F1),
2. a permanent's characteristics are its printed definition (F2), and
3. an ability is identified by its index in the printed ability list (F3).

### Solid and load-bearing (keep as is)

| Part | Why it survives |
| --- | --- |
| Explicit state machine + `state.pending` + `advance!` (ARCHITECTURE §2) | Exactly the right shape for MTG. Every hard system below is, at bottom, "suspend here, ask, resume". The principle is right; the problem (F1) is that it is applied only to turn steps, casting and combat damage, not generally. |
| Atomic decisions as plain frozen option hashes, validated by equality | RL-friendly, replayable, redactable. The one-point-at-a-time `assign_damage` pattern scales to division, trample, scry, ordering and search. |
| Transactional `apply`/`import` via Marshal copy (`Game#transaction`) | Generic. It needs no change as the state grows. |
| CR 400.7 new id on every zone change (`Engine#move!`) | Correct from day one. LKI (F5) builds on it, it doesn't fight it. |
| Primitive registry with path-addressed errors and generated docs | Good base for data-first cards. It needs *more categories* and *instances with parameters* (F7, F8), not a redesign. |
| Card types as composable modules (`type_modules`) | Fits Sagas, Battles, Rooms, Classes, Vehicles, if modules get hooks (F13). |
| Static/dynamic split; objects refer to definitions by id | Keeps state small and serializable. It needs an extension for tokens and copies (F12). |
| Deterministic PCG32, `Setup + seed` replay | Solid. Cross-version replay needs a policy (F15). |
| Per-viewer redaction on events and decisions | Already the right seam for scry, search, face-down and hidden choices. |
| `Steps::ORDER` step objects with `skip?` | A first-strike damage step slots in without a rewrite (F11). |

### Will need restructuring

| Part | Finding |
| --- | --- |
| Synchronous `resolve_top!` / SBA loop / mana abilities; ad-hoc suspended contexts (`state.casting`, `state.combat_damage`) | F1 |
| `definition(obj).creature?` / `keyword?` / `type?` / `.abilities` read directly at 25 call sites | F2 |
| Integer ability indices in state, options and stack objects | F3 |
| `state.effects` as untyped hashes with `kind == "pump"`, `duration == "end_of_turn"`, per-object P/T only | F4 |
| Events are write-only for the engine; no LKI; SBAs move objects one at a time | F5 |
| Direct mutators (`move!`, `deal_damage!`, `change_life!`, `draw!`, `add_counters!`) | F6 |
| Parameterless filter *classes*; fixed-count target lists | F7 |
| Integer-only amounts; no conditions or durations | F8 |
| Hard-coded cast sequence, hand-only casting, hand-rolled cancel rewind | F9 |
| Fixed-field `GameObject`/`PlayerState` structs duplicated in 4–5 places; catalog-only object identity | F12 |

The docs overstate the code in places (F18), which matters because agents read
the docs first.

---

## 2. Findings

### F1. No general way to suspend in the middle of a process: resolution, SBAs and mana abilities can't ask a question

**Severity:** Critical

**Blocks:** scry, surveil, search library, "you may", "choose one" on
resolution, "any player may pay", discard-a-card effects, sacrifice-a-creature
effects ("each opponent sacrifices a creature"), "choose a color/creature type"
on resolution, the legend rule (704.5j: controller chooses), ordering
replacement effects (616.1), APNAP trigger ordering (603.3b), choosing targets
for triggers, "add one mana of any color" (mana ability with a choice), cost
payments with choices (sacrifice which, discard which), explore, connive,
investigate+sacrifice, Saga chapters with choices. In practice, most Standard
cards.

**Where:**
- `engine/resolution.rb` `resolve_top!`: `ability&.effects&.each { it.apply(self, ctx) }`, then `give_priority!` in the same Ruby call.
- `engine.rb` `check_state_based_actions!`: a synchronous `loop`.
- `actions/activate_mana_ability.rb` and `engine/casting.rb#tap_for_payment!`: mana is produced synchronously.
- `state.rb`: every interruptible process so far has its own State field (`casting`, `combat_damage`, `attacks_declared`) with bespoke snapshot build/validation in `snapshot.rb`.

**Problem:** ARCHITECTURE §2 says "No Ruby call stack ever holds game
progress", but this holds only for turn steps, casting and combat damage. The
moment an effect in the middle of an effect list needs a decision, the Ruby
loop would have to stop. There is nowhere to store "resolving object X, effect
3 of 5, after the player picked card Y", so export, import and replay break.
Adding one State field per interruptible process (the current pattern) does not
scale. M2 alone needs about 10 such processes, and each would need its own
snapshot validation code.

**Recommendation:** Introduce a single serializable **frame stack** (an explicit
continuation stack) on `State`. Move `casting` and `combat_damage` into it.

```ruby
# state.frames : Array<Hash>, last = innermost. Plain JSON data only.
# {"type" => "resolve", "object" => "lightning_bolt#41", "pc" => 2,
#  "ctx" => {"controller" => 0, "source" => "...", "targets" => [...], "x" => 3,
#            "modes" => [1], "results" => [[...ids moved by effect 0...], ...]}}

module Enjine::Frames            # registry, like Decisions
  class Base
    # Runs until it is done or needs a decision.
    # Returns :done (pop me), :wait (I set state.pending), or :push (I pushed a child; call me again when it pops).
    def self.step(engine, frame) = raise NotImplementedError
    def self.validate(frame, data, errors) = nil     # used by Snapshot.validate
  end
end

# Engine#advance!
until state.pending || state.over?
  if (top = state.frames.last)
    case Frames.fetch(top["type"]).step(self, top)
    when :done then state.frames.pop
    when :wait then break
    when :push then next
    end
  else
    run_turn_machine!       # the current begin/done step logic
  end
end
```

Frame types to start with: `resolve`, `cast` (replaces `state.casting`),
`combat_damage` (replaces `state.combat_damage`), `sba`, `put_triggers`,
`mana_ability`, `replacement_choice`, `choose_cards` (generic "choose N of
these cards" for discard, sacrifice, search, scry and surveil).

Effects become resumable. Most effects need no choice and stay a one-liner.
The others get a `step` with local state:

```ruby
class Effect < Primitive
  # Default: no choices. Return :done.
  def run(engine, ctx, locals) = (apply(engine, ctx); :done)
end

class Scry < Effect          # locals persist in the frame between calls
  def run(engine, ctx, locals)
    locals["seen"] ||= engine.look_at_top!(ctx.controller, amount.value(engine, ctx))
    return engine.ask_choose_cards!(...) if locals["seen"].any?   # => :wait
    :done
  end
end
```

`EffectContext` must be serializable. Store it in the frame as a hash, and
rebuild the Struct on each step. Add `results` so later effects can refer to
what earlier ones did ("exile target creature. Its controller creates a…", "for
each card discarded this way"). Decisions stay in `Decisions::*`. Their `submit`
writes the answer into the top frame's locals and returns. Snapshot validation
of `pending` becomes "pending must belong to the top frame".

Rules for implementers:
- Put the cheap "no choice needed" path first so the common case stays fast.
- A decision that has exactly one option is still asked. That's the existing
  "no auto-skip" policy, and frames don't change it.
- Each frame type registers `validate`, so the fuzzer's invariant check stays
  complete.

**When:** Before any further M2 work: before triggers, scry/surveil/search, and
modal spells. It is the base the rest builds on.

**Effort:** M (move `casting` and `combat_damage` in; rewrite `resolve_top!`
and the SBA loop as frames).

---

### F2. Characteristics are read from the printed definition everywhere except P/T

**Severity:** Critical

**Blocks:** Vehicles/crew (a Standard staple: layer 4 type change), manlands,
"becomes a creature", animated lands, "gains flying/haste until end of turn"
(layer 6), "loses all abilities", anthems that grant keywords, protection from
a color (needs computed colors), changelings / "is every creature type",
control change (layer 2: `obj.controller` is mutated directly), copy effects
(layer 1), face-down, MDFC/transform faces, tokens.

**Where:** 25 `definition(...)` call sites: `engine/casting.rb` (8),
`engine/combat.rb` (3: `eligible_attackers`, `eligible_blockers`,
`attack_targets`), `engine/damage.rb` (2, including the SBA checks),
`engine/resolution.rb` (2), `engine.rb` (2, including
`summoning_sick_for_tap?` → `defn.keyword?(:haste)`), `mechanics/filters/filters.rb`
(`Filter.type?`), `mechanics/effects/effects.rb` (`Pump#apply` creature check),
`actions/*` (4), `view.rb`. `Characteristics#power_toughness(object)` is the
only computed characteristic, and it is computed **per object**.

**Problem:** CR 613 applies to *all* characteristics, and many rules read
characteristics: SBA (704.5f/g: "creature with toughness 0"), combat
eligibility, target legality, summoning sickness. Every direct
`definition(obj)` read will be wrong as soon as one layer 1–6 effect exists.
Computing per object is also structurally wrong. Whether creature A has the
anthem's bonus depends on whether anthem source B still *has* that ability
after layer 6 ("loses all abilities", 613.6, 613.8). So the computation must be
a **whole-board pass**, not `power_toughness(obj)`.

**Recommendation:**

```ruby
Characteristics = Data.define(
  :name, :mana_cost, :colors, :card_types, :supertypes, :subtypes,
  :abilities,          # Array<AbilityInstance> (see F3)
  :keywords,           # Hash name => params (see F11)
  :power, :toughness, :loyalty, :defense, :controller
) do
  def type?(t) = card_types.include?(t)
  def keyword?(k) = keywords.key?(k)
end

class Engine
  # Memoized whole-board result; invalidated whenever state changes.
  def chars(obj_or_id)
    @chars_epoch == state.epoch or (@chars = Layers.compute(self); @chars_epoch = state.epoch)
    @chars.fetch(id_of(obj_or_id)) { Layers.base_only(self, object(obj_or_id)) } # non-battlefield
  end
end
```

- `state.epoch` (an integer) is bumped in `Engine#emit`. Every mutation already
  emits an event, so the cache invalidates for free.
- `Layers.compute` starts from **copiable values**: `obj.base` = definition
  face, token definition or copy-effect result (F12). It applies layers 1–7
  (F4) to every battlefield object at once.
- Objects off the battlefield get base characteristics plus the effects that
  apply in their zone (rare). Stack objects use spell characteristics (601.2a).
- Replace every `definition(obj).creature?` / `keyword?` / `type?` /
  `.abilities` with `chars(obj)`. Keep `definition(obj)` for printed-only
  questions (deck limits, `rules_text`, the catalog id).
- **Guardrail:** add a spec that greps `lib/` and fails if `definition(` appears
  outside an allow-list (`layers.rb`, `view.rb` for printed text,
  `card_definition.rb`). Many agents will add mechanics, so this stops the
  bypass from coming back.

Do this as a pure refactor first, with zero effects, so `chars` = printed
values and the tests stay green. Then add layers (F4).

**When:** Before triggers (F5), because trigger conditions read
characteristics, and before any keyword work (F11).

**Effort:** M (mechanical refactor of 25 sites plus the guardrail; caching is S).

---

### F3. Abilities are identified by their index in the printed list

**Severity:** High

**Blocks:** granted activated abilities (Equipment "has {T}: …", "gains '{T}:
add one mana…'"), "loses all abilities", keyword abilities that expand into
real abilities (equip, crew, ward, flashback, ninjutsu, cycling: cycling is an
activated ability from *hand*), abilities that keep resolving after their
source loses them (113.7a), Class levels, Rooms, MDFC faces with different
ability lists, copy effects.

**Where:** `GameObject#ability` (integer); `state.casting["ability"]`; options
`{type: "activate", object:, ability: i}` and `{type: "activate_mana", …,
ability: i}`; `resolve_top!` → `definition(obj).abilities[obj.ability]`;
`CardDefinition#read_abilities` appends subtype-intrinsic abilities *after*
explicit ones, so indices already depend on subtypes (and layer 4 can change
subtypes).

**Problem:** Index `2` means "the third printed ability" only while the object
has exactly its printed abilities. With granted, lost or added abilities the
index is ambiguous or out of range. The **option hash shape is the public
API** for the RL project, so changing it later breaks every stored decision
log.

**Recommendation:** Give every ability a stable string reference, and carry the
ability's *data* with the stack object.

```ruby
AbilityInstance = Data.define(:ref, :ability, :origin)
#   ref:    "printed:2" | "face1:printed:0" | "intrinsic:forest" | "keyword:ward" |
#           "granted:eff#77:0"   (effect id + index in the granted list)
#   ability: the built primitive (StackAbility, ManaAbility, TriggeredAbility, ...)
```

- Options become `{type: "activate", object: id, ability: "printed:2"}`.
- A stack ability object stores `"ability_ref"` **and** `"ability_data"` (the
  canonical data hash of that ability). It is rebuilt via
  `Mechanics.build_entry` and memoized by the data hash. It then resolves even
  if the granting effect has ended or the source is gone (113.7a, 113.7b),
  and it needs no catalog lookup.
- Also store `"source_lki"` (the source's characteristics hash when the
  ability was activated or triggered) for "deals damage equal to its power"
  after the source was sacrificed (608.2h).

**When:** Together with F2, before triggers and before the decision API is
frozen for external consumers.

**Effort:** S–M.

---

### F4. The continuous effect model can't express static abilities, layers, dependencies or durations

**Severity:** Critical (for M3, and Standard is full of static abilities)

**Blocks:** anthems ("creatures you control get +1/+1"), lords, "can't"
restrictions, cost modification (statics), P/T *setting* (7b: "becomes 0/1",
"base P/T 4/4") versus *modifying* (7c), switching (7d), CDAs (`*`/`*`, 7a and
604.3), "loses all abilities" plus anthem interactions (613.8 dependency),
control change (layer 2), text/type/color changing (layers 3–5), "until your
next turn", "for as long as you control ~", "until end of combat", "this turn"
effects that aren't P/T, Vehicles.

**Where:** `engine/characteristics.rb`: `state.effects.each { next unless
effect["kind"] == "pump" … }`; `add_continuous_effect!` hard-codes
`"duration" => "end_of_turn"`; `cleanup_turn!` is the only effect-ending hook.
`GameObject` has no timestamp (613.7d: a permanent's timestamp is when it
entered the battlefield; 613.7e: attachment refreshes it).

**Problem:** There is no representation for (a) effects generated by static
abilities, which are not stored and whose affected set is dynamic (611.3a); (b)
layer and sublayer; (c) dependency ordering; (d) object timestamps; (e) any
duration but cleanup. Each new P/T effect would add another `kind == …` branch
in one method.

**Recommendation:** Two kinds of effect source feed one layer engine.

1. **Stored effects** (from resolution, 611.2: locked set) in `state.effects`:
   ```json
   {"id": "eff#41", "timestamp": 41, "source": "giant_growth#30", "controller": 0,
    "affected": {"locked": ["grizzly_bears#12"]},
    "op": {"modify_pt": {"power": 3, "toughness": 3}},
    "duration": {"until": "end_of_turn"}}
   ```
2. **Static effects** (611.3, 604) are generated on every `Layers.compute` from
   each object's *current* `StaticAbility` instances (after layers already
   applied, which is how "loses all abilities" removes an anthem). They are
   never stored:
   ```json
   {"static": {"affected": {"each": {"creature": {"controller": "you"}}},
               "op": {"modify_pt": {"power": 1, "toughness": 1}}}}
   ```

An **op** is a new primitive category `continuous`. Each op declares its layer:

```ruby
class Op < Primitive                     # category :continuous
  def self.layer = "7c"                  # one of 1a 1b 2 3 4 5 6 7a 7b 7c 7d
  def apply(chars_by_id, affected_ids, params) = ...
  def depends_on?(other, board) = false  # 613.8: other changes what I apply to, or what I do
  def cda? = false
end
# modify_pt(7c) set_pt(7b) switch_pt(7d) add_types/set_types(4) add_subtypes(4)
# grant_abilities/grant_keywords(6) lose_all_abilities(6) set_colors(5) gain_control(2) copy(1a)
```

`Layers.compute(engine)`:
1. Start every battlefield object from its copiable values (layer 1 first,
   since copy changes the base).
2. For each layer in order: collect active effects for the layer (stored ones
   plus static ones from objects that *still have* the ability now). Order
   them: CDAs first (613.3), then a topological sort by `depends_on?`, with
   ties and loops broken by timestamp (613.8b). Determine each effect's
   affected set *when the effect first applies* and keep it for the later
   layers (613.6). Apply.
3. Layer 7c includes counters (613.4c), as today.

Durations are a primitive category `duration`. Each value has an
`expired?(engine, effect, event)` hook, checked from `emit`, and one built-in
check in cleanup:
`end_of_turn`, `end_of_combat`, `until_your_next_turn` (expires on
`TurnBegan` of the controller), `while_source_on_battlefield` ("for as long as";
the effect is ignored as soon as the source id is gone), `while_controls`,
`indefinite`.

Add `timestamp` to `GameObject`, set in `move!` to battlefield and refreshed on
attach. Keep using the shared `next_id` counter for timestamps. It is
monotonic, which is all 613.7 needs.

**When:** Do the data model (effect record, op category, durations, object
timestamp) before M3 begins. Layers 1–3 (copy, control, text) can land
later, but the pipeline order must exist from the first static ability.

**Effort:** L.

---

### F5. No trigger infrastructure, and no last-known information

**Severity:** Critical

**Blocks:** every "when / whenever / at" (ETB, dies, attacks, "at the
beginning of your upkeep / end step", "whenever you cast", landfall, "whenever
you gain life"), ward (a triggered counter-unless-pay), Sagas (chapter
triggers), delayed triggers ("at the beginning of the next end step, return
it"), reflexive triggers ("when you do"), intervening-if (603.4), state
triggers (603.8), prowess, lifelink is *not* a trigger (see F11) but its
listeners are.

**Where:**
- `Engine#emit` forwards only to the Game buffer. The engine never reads its
  own events.
- `give_priority!`: SBAs, then priority. There is no "put triggered abilities
  on the stack" phase (117.5).
- `move!` deletes the old object. Nothing remains to "look back" at (603.10).
- `check_permanent_state_based_actions!`: `doomed.each { move! }` moves objects
  one at a time, so each death sees a different board (704.8 wants LKI from
  before *all* the simultaneous SBAs).
- `Events::ZoneChanged` carries `card/old_id/new_id/from/to/reason` but not the
  controller or characteristics at the time.
- `Events::DamageDealt` doesn't say whether the damage was combat damage.

**Problem:** The architecture doc says events "feed … triggered abilities
later". The event *types* are a good start, but triggers need three more things
the code doesn't have: (1) synchronous matching at emit time against the
*pre-event* board for leaves-the-battlefield and the post-event board for
others; (2) a persisted queue of pending triggers; (3) an LKI store.

**Recommendation:**

```ruby
# Ability primitive (category :ability)
{"triggered": {
   "when":   {"zone_change": {"from": "battlefield", "to": "graveyard", "subject": {"creature": {"other": true}}}},
   "if":     {"controls": {"filter": {"creature": {}}, "at_least": 3}},   # intervening-if (603.4)
   "optional": true,                                                       # "you may"
   "targets": [...], "effects": [...] }}

# New primitive category :trigger with event matchers:
# enters, zone_change (dies = battlefield->graveyard), attacks, blocks, becomes_blocked,
# deals_damage{combat?, to}, cast{filter}, step_begins{step, whose}, life_gained, cards_drawn,
# counters_added, becomes_target{by: opponent}  (ward), state{condition} (603.8)
```

Engine side:

1. `Engine#emit(event)` → `TriggerWatcher.observe(self, event)` *before*
   buffering. The watcher indexes triggered abilities by matcher event type
   (performance) and checks:
   - battlefield objects' current `chars(...).abilities` (post-event),
   - for leaves-the-battlefield events: the LKI of objects that just left
     (603.10a), which may include the leaving object itself ("when ~ dies"),
   - abilities that work from other zones (graveyard, hand),
   - `state.delayed_triggers`.

   A match appends to `state.pending_triggers`:
   ```json
   {"controller": 0, "source": "grizzly_bears#12", "source_lki": {...chars...},
    "ability_ref": "printed:1", "ability_data": {...}, "event": {...event.to_h...}}
   ```
2. **LKI:** in `move!`, before deleting the old object, store
   `state.lki[old_id] = chars(old).to_h` plus status (tapped, counters,
   attached_to). Clear entries at the end of `put_triggers` once nothing
   references them. Stack objects keep their own `source_lki` copy (F3).
3. **Simultaneous batches:** SBAs, combat damage and "destroy all" compute the
   whole batch and snapshot LKI for every member *first*, then perform the
   moves. Wrap this as `engine.batch { … }` so watchers see a consistent
   pre-batch board.
4. **Placement:** in `give_priority!`, run the 117.5 loop as a frame: SBAs →
   if any pending triggers → `put_triggers` frame. It goes in APNAP order. A
   player with 2 or more triggers gets an `order_triggers` decision (pick the
   next one, one per decision). Each trigger is then announced with the same
   target-choice stages as casting (F9), with no cost and no cancel. A
   trigger with no legal targets is removed (603.3d). An intervening-if is
   checked when it triggers and again on resolution. Then repeat SBAs.
5. Cleanup (514.3a): if SBAs or triggers happen in cleanup, give priority and
   then run another cleanup step. Today `Cleanup#priority?` is a fixed `false`.
6. Enrich events now (cheap; it also helps the CLI): `ZoneChanged` gets
   `controller`; `DamageDealt` gets `combat: bool` and `source_card`; add
   `Events::CardsDrawn`, `LifeGained`/`LifeLost` (or derive from
   `LifeChanged`), and `BecameTarget`.

**When:** M2 (it *is* M2), right after F1–F3.

**Effort:** L.

---

### F6. State changes can't be replaced or prevented

**Severity:** High

**Blocks:** "enters tapped" (most Standard dual lands: "enters tapped unless…"),
"enters with N +1/+1 counters", "if it would die, exile it instead", "if you
would draw, instead…", "damage can't be prevented", prevention shields (615),
regenerate (701.19), indestructible versus destroy, "if a source would deal
damage, it deals double", "as ~ enters, choose a color" (614.12 and 614.1c),
617/616 ordering, Rooms entering, "enters as a copy" (clones; 614.1c/616.1c),
token doublers, the flashback "exile instead of graveyard" rule.

**Where:** `Engine#move!`, `Damage#deal_damage!`, `change_life!`,
`add_counters!`, `draw!`, `destroy` (calls `move!` directly). `move!` already
hard-codes one ETB modification: `fresh.counters["loyalty"] = loyalty`
(306.5b).

**Problem:** Replacement effects (614.1) modify an event *before it happens*.
That requires every mutation to go through a "proposed event" stage. Today the
mutation and the event emission happen together, after the fact, inside each
helper. Adding replacements later means touching every mutator *and* every
caller, especially callers that loop (combat damage, "destroy all").

**Recommendation:** Split *propose* from *execute*:

```ruby
Proposal = Struct.new(:kind, :data, :applied)   # kind: :zone_change, :damage, :life, :draw, :counters, :tap, :create_token
# data example: {"object" => id, "from" => "battlefield", "to" => "graveyard", "cause" => "destroy",
#                "enters" => {"tapped" => false, "counters" => {}, "controller" => 0}}

def perform(proposals)                     # always a batch (simultaneity, 704.7)
  proposals.each do |p|
    loop do
      candidates = Replacements.applicable(self, p) - p.applied   # 614.5: each applies at most once
      break if candidates.empty?
      chosen = choose_replacement(p, candidates)  # 616.1a-f ordering; may push a frame (F1) -> :wait
      chosen.apply!(p)                            # may rewrite p, or replace it with other proposals
      p.applied << chosen.id
    end
  end
  execute!(proposals)                      # today's mutation code + emit
end
```

- Replacement and prevention effects are a `replacement` primitive category.
  They are produced like static effects (from current characteristics) and
  from stored effects (prevention shields with a remaining amount).
- **Self-replacement first** (616.1a). The decider is the affected object's
  controller (or owner) or the affected player (616.1). Only ask when 2 or
  more effects apply that the player could order differently. That is still a
  real decision (the no-auto-skip policy applies), but it is rare.
- **ETB replacements (614.12)** evaluate the permanent as it would exist on
  the battlefield: build a hypothetical `Characteristics` for the incoming
  object. Move the loyalty-counter line out of `move!` into the planeswalker
  type module's `entering_status` hook.
- Card data:
  ```json
  {"replacement": {"self_enters": {"tapped": true, "unless": {"controls": {"filter": {"land": {"subtypes": ["island"]}}}}}}}
  {"replacement": {"self_enters": {"counters": {"+1/+1": {"x": {}}}}}}
  {"replacement": {"would": {"zone_change": {"subject": "self", "to": "graveyard"}}, "instead": {"to": "exile"}}}
  ```
- Do **ETB-tapped and enters-with-counters first**. They cover a large share
  of Standard lands and creatures, need no ordering decision in practice, and
  prove the propose/execute split.

**When:** Do the propose/execute split (a refactor, no new behaviour) during
M2, before triggers multiply the call sites. Full 616 ordering at M3. Pull
"enters tapped" forward (see the build order).

**Effort:** M for the split, L for full 614–616.

---

### F7. Filters and targets can't take parameters

**Severity:** High

**Blocks:** "target creature you control", "target nonland permanent",
"target creature with flying", "creature card in your graveyard" (reanimation,
recursion), "another target", "up to two targets", "any number of", divided
damage (601.2d), mana-value filters, "target spell or ability", "activated or
triggered ability" targets (Stifle effects), "attacking creature", hexproof,
shroud, protection, ward (target legality), modal per-mode targets.

**Where:** `mechanics/filters/filters.rb`: filters are **classes**.
`Filter.build` runs `check_keys(params, [])` and returns `self`.
`candidates` uses `engine.state.public_send(zone)`, so it can only reach shared
zones (battlefield, stack). Per-player graveyards, hands and libraries are
unreachable. `StackAbility.parse_targets` builds a flat list, one target per
entry. `Selector.build_hash` validates `target` index against a static
`targets_count`.

**Problem:** Almost no Standard removal or recursion spell is expressible
without qualified filters. Because filters are classes with no state, every
qualification would become a new registered primitive (`creature_you_control`,
`nonland_permanent`, …): a combinatorial explosion that conversion agents
cannot predict.

**Recommendation:** Make filters **instances built from parameters**. Keep the
bare-string form as shorthand, so existing data stays valid.

```json
"creature"                                                        // unchanged
{"creature": {"controller": "you"}}
{"permanent": {"not_types": ["land"], "mana_value": {"lte": 3}}}
{"card": {"zone": "graveyard", "owner": "you", "types": ["creature"]}}
{"creature": {"keywords": ["flying"], "other": true}}
{"any_of": [{"creature": {}}, {"planeswalker": {}}]}
{"spell": {"types": ["creature"]}}     {"ability": {"kinds": ["activated", "triggered"]}}
```

Common predicate keys live in the base class: `controller`, `owner`, `zone`,
`types`, `not_types`, `subtypes`, `supertypes`, `colors`, `keywords`,
`mana_value`/`power`/`toughness` comparisons, `tapped`, `attacking`, `other`,
`token`. All of them read `chars(...)` (F2). Context-relative keys (`other`,
"you") need `FilterContext(controller:, source:)`.

Target specs become objects, with the string as shorthand:

```json
"targets": [{"filter": {"creature": {}}, "count": 2, "min": 0, "distinct": true, "divide": "damage"}]
```

Selector `{"target": 0}` then refers to the *spec index*. Add
`{"target": 0, "each": true}` for all chosen objects of a multi-target spec.
New selectors: `{"result": 0}` ("the card exiled this way"), `"event_subject"`
("that creature", for triggers), `"source_controller"`, `"target_controller"`.

Centralize target legality in one `targetable?(engine, ref, by_source_chars,
by_controller)`. Today `legal_targets` calls `spec.match?`. The new check
consults hexproof, shroud, protection and "can't be the target of" restrictions
(via the rules-query hooks in F11). It is used both when choosing targets and
at resolution (608.2b).

**When:** M2. Needed before any meaningful Standard card batch converts.

**Effort:** M.

---

### F8. Amounts, conditions, durations, choices and turn history don't exist in the data model

**Severity:** High

**Blocks:** X spells, "equal to the number of …", "equal to its power",
kicker ("if this spell was kicked"), "if you control …", "unless … pays",
"you may", "choose one —", "for each", "this turn" history conditions ("if a
creature died this turn", "if you gained life this turn", descend, "the
second spell you cast each turn"), threshold-like counts, "until your next
turn".

**Where:** `Mechanics.integer_param(… min: 0)` is the only amount type.
`Primitive::CATEGORIES = %i[type supertype subtype keyword ability cost effect
filter]`. DESIGN §2 promises "triggers, conditions, amounts, keywords,
continuous effects, replacements", but four of these categories don't exist.
There is no per-turn statistics store.

**Problem:** Every Standard set leans on variable amounts and history
conditions. These are cheap to add *if* every primitive reads values through
a common interface from the start. If many effects keep their own hard-coded
`Integer` reads, each one must be migrated later.

**Recommendation:** Add the categories now: `amount`, `condition`, `duration`,
`trigger`, `continuous`, `replacement`. An integer literal stays valid
everywhere an amount is allowed (no data break).

```json
"amount": 3
"amount": {"x": {}}
"amount": {"count": {"creature": {"controller": "you"}}}
"amount": {"power_of": {"target": 0}}
"amount": {"sum": [{"x": {}}, 1]}
"amount": {"turn_stat": {"stat": "life_gained", "player": "you"}}

"if":     {"all_of": [{"controls": {"filter": {"artifact": {}}, "at_least": 2}}, {"not": "kicked"}]}

"effects": [
  {"may":    {"effects": [...]}},                                   // 609.3 "you may"
  {"if":     {"condition": ..., "then": [...], "else": [...]}},
  {"unless": {"player": "target_controller", "pays": [{"mana": "{2}"}], "effects": [...]}},
  {"repeat": {"times": {"count": ...}, "effects": [...]}}            // "for each"
]
```

- `Amount#value(engine, ctx) -> Integer`, `Condition#holds?(engine, ctx)`.
  Each is a registered primitive (so it is documented in `SUPPORTED.md`).
- Replace `Mechanics.integer_param` with `Mechanics.amount_param` in every
  effect *now*, while there are only 8 effects.
- Modes belong to the *ability* (601.2b: chosen while casting), not to the
  effect list:
  ```json
  {"spell": {"choose": {"count": 1}, "modes": [{"targets": [...], "effects": [...]}, {...}]}}
  ```
- `state.turn_stats`: a small hash per player (`spells_cast`, `life_gained`,
  `creatures_died`, `cards_drawn`, `attacked_with`, `descended`, …). A watcher
  updates it from events and resets it on `TurnBegan`. Conditions read it.
  Deriving these from the history log is too slow and couples rules to
  history.

**When:** M2, alongside F7. The `amount_param` swap can happen immediately.

**Effort:** M.

---

### F9. Casting is a fixed sequence; no additional or alternative costs, X, modes, or casting from other zones; cancel is a hand-written rewind

**Severity:** High

**Blocks:** X costs, kicker and other additional costs (sacrifice, discard,
pay life, "exile a card from your graveyard"), alternative costs, flashback,
casting from exile ("you may play that card this turn": impulse draw, very
common in Standard), plot, foretell, Adventures, MDFC back faces, cycling (an
activated ability in hand), convoke, delve-like costs, cost increases and
reductions (601.2f), Treasure (sacrifice for mana *during* payment), ward
payment, division (601.2d), choosing modes (601.2b).

**Where:** `engine/casting.rb`: `continue_casting!` = targets → pay mana →
finish. `begin_cast!` reads `player(index).hand`, and `origin` assumes hand.
`start_casting!(cost: defn.mana_cost)`. Non-mana ability costs are paid in
`pay_ability_costs!` at the end, without choices. `cancel_casting!` untaps
listed sources, restores the pool and `restore_to_hand!` rebuilds a hand
object field by field. `Actions::Cast` enumerates the hand only. `castable?`'s
`affordable?` is a mana-value bound.

**Problem:** 601.2 has nine sub-steps (a–i). The engine implements three of
them as hard-coded methods. A hand-written rewind can't stay correct once
costs or mana abilities do more than tap: a Treasure sacrificed for mana gets a
*new object id* in the graveyard, a paid life total changes, a discarded card
moves zones.

**Recommendation:**

1. A **`cast` frame** (F1) running declarative **stages**, each a small class:
   ```ruby
   CAST_STAGES = [Stages::ChooseMethod,    # which permission/face/alt cost (601.2b)
                  Stages::Modes, Stages::ChooseX, Stages::AdditionalCosts,
                  Stages::Targets, Stages::Divide,
                  Stages::TotalCost,       # 601.2f: base|alt + additional + increases - reductions; locked in
                  Stages::PayCosts,        # 601.2g-h: mana one unit at a time; other costs as choices
                  Stages::Finish]          # 601.2i: becomes cast, cast triggers (F5)
   # each: needed?(engine, ctx) -> bool ; ask(engine, ctx) -> pending ; submit(engine, ctx, option)
   ```
   Activation (602.2) and putting triggers on the stack (603.3d) reuse the
   same stages with different lists.
2. **Cast permissions** replace the hand-only enumeration:
   ```ruby
   CastPermission = Data.define(:object, :face, :zone, :cost, :timing, :after_resolution)
   engine.cast_permissions(index)  # hand (normal), graveyard (flashback), exile ("may play this turn",
                                   # adventure), stack-face choices (MDFC, split); from static abilities and
                                   # stored effects with durations
   ```
   `Actions::Cast` offers `{type: "cast", object: id, method: "normal"|"flashback"|"face:1"|…}`.
   Land plays get the same treatment (play from top of library; MDFC land
   backs; extra land drops come from effects, not the `LANDS_PER_TURN`
   constant).
3. **Cost primitives** gain choice support:
   `choices(engine, ctx) -> [candidate refs]`, `min/max`, `pay!(engine, ctx,
   chosen)`. Sacrifice, discard, exile-from-graveyard, pay life, tap untapped
   creatures (crew, convoke), remove counters.
4. **Cancel via checkpoint**, not by hand: when the cast frame starts, store
   `frame["checkpoint"] = state.to_h` (without frames), and restore it with
   `Snapshot.build` on cancel. This is CR 733.1 ("the entire action is
   reversed") done mechanically. It works for any cost or mana ability with
   side effects. The history entry keeps the events plus `CastCancelled`;
   document that consumers must treat the events of a cancelled cast as
   reverted. The checkpoint roughly doubles the size of a mid-cast snapshot,
   which is acceptable.
5. Keep `cancel` available in every stage. `affordable?` can stay a cheap
   upper bound (a dead-end cast is cancellable). For RL quality, consider
   tightening it later with colour checks.

**When:** Stages and permissions in M2, before modal, X and kicker cards.
Checkpoint cancel *before* the first non-tap cost or Treasure.

**Effort:** L.

---

### F10. Mana costs and pools can't represent hybrid, Phyrexian, X, snow, choices or restrictions

**Severity:** Medium (High for Standard deck coverage)

**Blocks:** hybrid and Phyrexian symbols, `{X}`, `{S}`, "add one mana of any
color" (most Standard dual or tri lands and many creatures), "spend this mana
only on …", Treasure-produced mana tracking, pain lands (pay life as part of
a mana ability), cost reduction of generic or colored parts, convoke paying a
colored symbol.

**Where:** `mana.rb`: `Cost = Data.define(:generic, :colored)`. The pool is a
`Hash` from type to count. `parse_produce` returns fixed types.
`state.casting["remaining"]` is a per-colour counter.

**Problem:** `generic + colored` can't represent symbols with alternatives. A
pool of counts can't carry restrictions or sources.

**Recommendation:**
- `Cost = Data.define(:symbols)`. Each symbol is `Generic(n)`, `Colored(c)`,
  `Hybrid([a, b])`, `Phyrexian(c)`, `X`, `Snow` or `Colorless`. `to_s` must
  render exactly today's canonical strings, so stored card rows don't change.
  The `remaining` state becomes a list of unpaid symbols, and paying offers
  "pay symbol i with mana unit j" (or keep today's per-type option and
  auto-match a symbol deterministically: fewer decisions, same legality).
- Pool = list of units `{"type": "R", "source": id, "restrictions": [...]}`.
  `ManaEmptied` stays the same.
- Mana ability `produce` accepts `{"any_color": 1}`, `{"one_of": ["W", "U"]}`
  or `{"amount": …}`. Since F1, a mana ability may ask a choice, as a
  `mana_ability` frame that is still not on the stack (605.3b).

**When:** Before converting Standard mana bases (pull it early; see the build
order). Hybrid, Phyrexian and snow can wait.

**Effort:** M.

---

### F11. Keywords are bare names checked inline; combat has no rules-query hooks

**Severity:** High (the evergreen combat keywords are on most Standard creatures)

**Blocks:** flying/reach, first strike/double strike (an extra damage step),
trample (lethal assignment, including deathtouch, and attacking planeswalkers),
menace (2 or more blockers: a whole-declaration check), vigilance, lifelink
(part of the damage event, not a trigger: 702.15b), deathtouch (704.5h flag,
1-is-lethal), indestructible, hexproof, ward (triggered), protection (DEBT:
damage, enchant/equip, block, target), defender, "can't block", "attacks each
combat if able", parameterized keywords (ward {2}, toxic 2, protection from
red, "ward—pay 3 life").

**Where:** `mechanics/keywords/basic.rb`: `Flash` and `Haste` are empty
classes, consulted only through `defn.keyword?(:haste)` /
`instant_speed?`. `CardDefinition#read_names` accepts strings only.
`Combat#eligible_blockers`, `declare_blocker!` (blocker→single attacker),
`deal_combat_damage!` (a single blocker gets all the damage automatically),
`Steps::ORDER` (one `combat_damage` step).

**Problem:** Each keyword would otherwise be another `if keyword?(:x)` inside
combat and casting code. That spreads one rule across many files (against the
"ONE PLACE PER MECHANIC" folder goal), and it can't be shared with the
non-keyword static restrictions ("creatures can't block this turn") that
apply the same rules.

**Recommendation:**

1. A **rules-query hook registry** (101.2: "can't" beats "can") that keywords
   *and* static restrictions register into:
   ```ruby
   Rules.query(:can_block?, engine, blocker:, attacker:)       # all hooks must allow
   Rules.query(:can_attack?, engine, creature:, target:)
   Rules.query(:attack_causes_tap?, engine, creature:)         # vigilance
   Rules.query(:min_blockers, engine, attacker:)               # menace -> 2 (max over hooks)
   Rules.query(:lethal_damage, engine, source:, creature:)     # deathtouch -> 1
   Rules.query(:targetable?, engine, ref:, source_chars:, controller:)  # hexproof, protection, shroud
   Rules.query(:can_be_destroyed?, engine, object:)             # indestructible (702.12b)
   Rules.query(:damage_step, engine, creature:)                 # :first, :regular, :both
   ```
   A keyword primitive declares the hooks it implements. A
   `{"static": {"restriction": "cant_block", "affected": …}}` registers the
   same hook through the layer pass.
2. **Parameterized keywords** in the data. The string form stays valid:
   `"keywords": ["flying", {"ward": {"cost": [{"mana": "{2}"}]}}, {"protection": {"from": {"color": "red"}}}, {"toxic": 2}]`.
   `Characteristics#keywords` is a Hash from name to params, so a creature can
   have it twice where that matters (e.g. two ward instances).
3. **Keywords that are abilities** expand into `AbilityInstance`s (F3):
   ward → triggered ability with `becomes_target{by: opponent}` and `unless
   pays → counter`; equip and crew → activated; flashback → cast permission
   plus an exile replacement. They get the ref `"keyword:<name>:<n>"`.
4. **Combat:**
   - Add a `first_strike_damage` step to `Steps::ORDER` before
     `combat_damage`. It is skipped unless an attacker or blocker has first
     or double strike at the start of combat damage (510.4). Regular damage
     then excludes creatures that already dealt first-strike damage unless
     they have double strike. The current `skip?` design handles this
     without a rewrite.
   - Damage assignment (510.1c–d; there is no damage assignment order in the
     current CR): keep one point per decision. Always ask when a blocked
     attacker has trample, or has 2 or more blockers. Add the defending
     player or planeswalker as an option only when every blocker has been
     assigned lethal damage, using `Rules.query(:lethal_damage)` (which
     accounts for damage already marked and for deathtouch).
   - Declarations: validate the whole set on `done`. Offer `done` only if the
     declaration is legal (menace, 509.1c requirements). Add an `undeclare`
     option, otherwise a defender who blocked a menace attacker with one
     creature and has no other creatures is stuck.
   - Change `state.blockers` to `blocker → [attackers]` now (cheap) for
     "can block an additional creature".
   - Damage results go through the proposal pipeline (F6): lifelink gains
     life *as part of* the damage event, deathtouch sets
     `status["deathtouch_damage"] = true` for SBA 704.5h, toxic and infect add
     counters.
5. Legend rule (704.5j) is an SBA with a choice, so it needs the `sba` frame
   (F1).

**When:** Pull flying, reach, vigilance, menace, first/double strike, trample,
deathtouch, lifelink, indestructible, hexproof and defender **forward from M4
to right after F2/F5**, before M3 (see the build order). They cover most
Standard creatures and most of them need no layers. Ward needs triggers (F5)
and protection needs colors (F2).

**Effort:** M for the hooks plus the static keywords; M for the combat rework.

---

### F12. The object and player model is rigid: fixed structs, catalog-only identity, no tokens

**Severity:** High

**Blocks:** tokens (Treasure, Clue, Food, Blood, Map, Incubator, creature
tokens: on very many Standard cards), token copies, copies of cards (707),
Auras and Equipment (`attached_to`), face up/down, transformed and MDFC face,
phasing, linked "exiled with" (607), "chosen color/type/name" memory, X and
kicked/modes memory for permanents ("if it was kicked, it enters with…"),
Saga lore and Class levels, Room unlock state, battles (defense), emblems
(command zone), player counters (poison exists; energy, rad, experience
don't), player designations (speed, monarch, initiative, day/night).

**Where:**
- `state.rb`: `GameObject = Struct.new(14 positional fields)`. The full field
  list is spelled out again in `Engine#create_object`,
  `Casting#restore_to_hand!`, `Snapshot.build_object`, `GameObject#to_h` and
  the `Snapshot.validate_object*` helpers.
- `PlayerState` has the same problem, plus `PLAYER_KEYS`.
- `Snapshot.validate_object` requires `id =~ /\A([a-z0-9_]+)#(\d+)\z/` with
  `match[1] == obj["card"]` and `catalog.include?(obj["card"])`.
- `State::ZONES` has no command zone.
- Counter kinds are restricted to `COUNTER_KINDS = %w[+1/+1 -1/-1 loyalty]`
  by both the effect and the snapshot validator.

**Problem:** Every Standard-relevant permanent feature adds a field, and each
field addition touches five or six places. Tokens have no catalog definition,
so they can't be created at all under the current identity rules.

**Recommendation:**
1. **Field table instead of positional structs:**
   ```ruby
   OBJECT_FIELDS = {
     "id" => [nil, String], "card" => [nil, String], "owner" => [nil, Integer], ...
     "timestamp" => [nil, Integer], "face" => [0, Integer],
     "status"  => [{}, Hash],   # 110.5: tapped, face_down, phased_out, transformed, attached_to, deathtouch_damage
     "memory"  => [{}, Hash],   # choices locked in: x, kicked, modes, chosen_color, exiled_with, cast_from
   }
   ```
   Generate `to_h`, `from_h` (missing key → default, so old snapshots load),
   `new_object(**overrides)` and type checks from the one table. Snapshot
   validation iterates the table. Do the same for `PlayerState` (add
   `counters` for poison/energy/rad and `designations`).
2. **Tokens compiled into the catalog at Setup time.** Token definitions live
   inside the creating card's data:
   `{"create_token": {"token": {"name": "Treasure", "types": ["artifact"], "subtypes": ["treasure"], "abilities": [...]}, "amount": 1}}`.
   Predefined tokens (111.10) ship as named presets:
   `{"create_token": {"preset": "treasure"}}`. When a card loads,
   `CardDefinition` collects its nested token definitions and the `Catalog`
   registers them under synthetic ids (`token.treasure`,
   `token.<card_id>.<n>`). Then `object.card` is still a catalog id,
   snapshots still validate against the catalog, and nothing token-related
   has to live in state. Loosen the snapshot id regex to allow `.`.
   `GameObject` gets `"kind" => "token"`. Add SBA 704.5d (a token off the
   battlefield ceases to exist).
3. **Copies (707)** are layer-1 effects whose op stores the copiable values
   as a reference (`{"copy": {"card": "…", "face": 0, "except": {...}}}`), not
   a new definition. Token copies use `card` = the copied card's id plus a
   copy effect, so no runtime-built definitions are ever needed.
4. **Counters:** open `COUNTER_KINDS` into a registry. Each counter kind is a
   primitive declaring its rules effect: +1/+1 and -1/-1 (layer 7c and SBA
   704.5q annihilation), keyword counters (122.1b: they grant keywords in
   layer 6), shield, stun, lore, defense, finality, oil and generic named
   counters.
5. Add the `command` zone (emblems).

**When:** The field table now (S). It is pure refactoring and makes every
later finding cheaper. Tokens in M2, because Treasure, Clue and Food are on a
large share of Standard cards.

**Effort:** S (table) + M (tokens/counters/command zone).

---

### F13. Single-face card definitions; layouts and special frames have no home

**Severity:** Medium (High for Standard coverage: MDFCs, Adventures, Rooms,
Sagas, Classes and Cases appear regularly in recent Standard sets; verify
against the current Standard set list)

**Blocks:** MDFCs (712; modal land backs are common), transforming DFCs (Day
/night, "transform ~"), Adventures (715), split cards and Rooms (709, 709.5),
Sagas (714), Classes (716), Cases, battles (310), prototype, flip cards (old,
low priority).

**Where:** `CardDefinition::KEYS` is one flat face. The conversion guide says
to skip multi-face cards. `Catalog` slugs only the full name, and decklists
reference that name. There is no `face` on `GameObject`.

**Problem:** Today any face-related field would end up next to the card-level
fields. If that happens ad hoc, the format gets two incompatible ways of
expressing a face.

**Recommendation:** Settle the shape now, even if only `normal` is
implemented:

```json
{ "name": "Bala Ged Recovery // Bala Ged Sanctuary", "layout": "modal_dfc",
  "faces": [
    { "name": "Bala Ged Recovery", "mana_cost": "{2}{G}", "types": ["sorcery"], "abilities": [...] },
    { "name": "Bala Ged Sanctuary", "types": ["land"], "abilities": [...] } ] }
```

- Face-level keys: today's characteristic keys (`name mana_cost types
  supertypes subtypes keywords power toughness loyalty defense abilities
  color_indicator rules_text`). Card-level keys: `name`, `layout`, `faces`,
  `format` (F14).
- A card with no `faces` is one implicit face, so existing data needs no
  change. `CardDefinition` exposes `faces`, and today's accessors delegate to
  `faces[0]`, so existing callers keep working during the transition.
- `layout` is a new primitive category. It is the right place for the rules
  that differ per layout: characteristics in each zone (709.4, 712.8, 715.4),
  which faces can be cast or played (feeds F9 cast permissions), where the
  card goes after resolution (an Adventure goes to exile with a permission),
  and how `transform` flips `GameObject.face`.
- `Catalog` indexes by full name and by each face name. Decklists accept
  either.
- Sagas, Classes, Cases, Rooms and battles are **subtype/type modules with
  hooks** (`entering_status`, `sba`, `abilities_available(obj)`), plus state
  in `status`/`counters`. The existing composition design fits this well:
  a Saga is "lore counter on ETB and precombat main (714.3b)" + chapter
  triggers on `counters_added{lore}` + SBA 704.5s. Room: two faces,
  `status["unlocked"] = [0]`, unlock = special action 116.2m.

**When:** Freeze the JSON shape (and the `layout: normal` default) before the
conversion pipeline stores many rows. Implement MDFC and Adventure in M3/M4.
Their cast-permission part depends on F9.

**Effort:** S (shape and delegation), M per layout.

---

### F14. The card data format has no schema version, and its "canonical form" isn't canonical for abilities

**Severity:** Medium

**Blocks:** safely evolving any primitive's parameters; re-running conversions
without spurious `CatalogConflict`.

**Where:** `CardDefinition#normalize`: top-level fields are normalized, but
`out["abilities"] = deep_stringify(card["abilities"])` copies the *input* as
it came. `Catalog#add` raises `CatalogConflict` when `to_h` differs. The
guide tells pipelines to store `to_h` and `engine_version`. There is no
`format` key, and `KEYS` rejects unknown keys (good for strictness, but it
means a newer card row fails hard on an older engine).

**Problem:** Two semantically identical cards that differ cosmetically (for
example `{"gain_life": {"amount": 3}}` versus `{"gain_life": {"amount": 3,
"to": "you"}}`, or `"targets": []` present versus absent) are "different
definitions" and raise `CatalogConflict` when two decks meet. When a
parameter's shape changes (F7 turns target strings into objects, F8 turns
integers into amounts), old rows have no defined upgrade path.

**Recommendation:**
- Optional top-level `"format": 1`. If it's absent, read it as 1. Add
  `CardDefinition::UPGRADES = { 1 => ->(h) { … returns format-2 hash } }`,
  applied in `from_h` before validation. Bump the format only for breaking
  shape changes. *Additive* changes (new optional keys, new primitives,
  integer→amount where integers stay valid) don't bump it.
- Each primitive implements `to_data` (canonical params, with defaults
  either always present or always omitted). `normalize` emits
  `abilities.map(&:to_data)` instead of copying the input. `CatalogConflict`
  then compares semantic forms.
- Policy written into `docs/guides/adding-a-mechanic.md`: never rename or
  re-type an existing param. Add a new one, and keep the old one as an
  accepted alias that `to_data` rewrites.
- Validation report: add `"format"` next to `engine_version`.

**When:** Before the conversion pipeline stores rows at scale. The cheapest
moment is now.

**Effort:** S–M.

---

### F15. Snapshots, events and history have no evolution strategy

**Severity:** Medium

**Blocks:** loading old exports after any state change (every F above changes
state); replaying RL decision logs across engine versions; detecting that a
snapshot's cards changed.

**Where:**
- `Snapshot::VERSION = 1`. `validate` returns an error unless `version ==
  VERSION`, and there is no upgrade path.
- `State#to_h` records `rules` but not `engine_version` or a catalog
  fingerprint.
- `Events.from_h` builds `klass.new(**members → hash[m])`: missing fields
  silently become `nil`, renamed fields are silently dropped, and unknown
  event types raise.
- Exports embed the full history, events included.
- `Game#decision_log` stores bare options. If a later engine adds a decision
  point (trigger ordering, replacement ordering, a new cost choice), replaying
  an old log fails with a confusing `IllegalDecision`, or worse, a
  same-shaped option is accepted for a different decision.

**Recommendation:**
1. `Snapshot::UPGRADES = {1 => ->(data) { …v2 }, 2 => …}`. `load` upgrades
   step by step, then validates. With the F12 field table, most upgrades are
   just "add field with default".
2. Write `"engine_version"` and `"catalog_digest"` (SHA-256 of the canonical
   definitions of every card id referenced) into the snapshot. On import, a
   digest mismatch is an `InvalidSnapshot` error (or a warning with an
   explicit `allow_catalog_drift:` flag). Otherwise an old snapshot can
   silently play a re-converted card with different text.
3. Events: give each event type a `version` and an optional `upcast` block.
   `from_h` fills declared defaults and drops unknown keys explicitly (logged
   in tests). Treat the event stream shape as public API, documented in
   `docs/reference` (generated, like the primitives).
4. Decision logs: record `[kind, option]` pairs (the history already has
   `kind`). The replayer checks that the pending kind matches before
   submitting, so a version mismatch fails fast with a precise message. State
   the policy plainly in DESIGN §6: *replay is guaranteed only within the
   same `engine_version` + `catalog_digest`*. Training data stores seed,
   engine_version and digest, not only the seed.
5. Treat the option-hash shapes (F3 ability refs, F9 cast methods) as frozen
   once the RL project consumes them. Get them right in M2.

**When:** Items 2 and 4 immediately (S). Item 1 before the first state shape
change ships to anyone who keeps exports. Item 3 alongside F5 (events grow).

**Effort:** S–M.

---

### F16. The decision API assumes fully enumerable options and incremental declarations that are always completable

**Severity:** Medium

**Blocks:** naming a card ("choose a card name", open domain), "pay any
amount of life", large X, menace and requirement legality of a whole
declaration, "choose two different targets", dividing damage among N targets,
search a 40-card library (fine), scry/surveil ordering (fine if sequential).

**Where:** `Game#submit`: `decision.options.include?(chosen)`.
`Decisions::*.options` must return a full list. Declarations are incremental
with no undo (`declare_attacker!`, `declare_blocker!`).

**Problem:** For most of MTG the sequential, one-choice-at-a-time pattern
works and suits RL. Two gaps remain: (1) open domains can't be enumerated;
(2) a sequence of locally legal picks can lead to a globally illegal state
with no way out.

**Recommendation:**
- Allow a decision class to return a **domain descriptor** instead of a list
  when the domain is open: `{"domain": {"type": "integer", "min": 0, "max":
  20}}` or `{"type": "card_name"}`. Add `legal?(engine, pending, option)` for
  validation. `Game#submit` uses `legal?` when it's defined and `include?`
  otherwise. Keep enumerations wherever the domain is finite and reasonably
  small (RL action masking prefers them).
- Every declaration frame (attackers, blockers, targets with `distinct`,
  divide) offers `done` only when the current set is legal, and offers an
  `undo` / `remove` option. A cheap feasibility look-ahead (for example,
  offer a blocker on a menace attacker only if a second eligible blocker
  exists) is a nice-to-have. `undo` is the guarantee.
- Ordering decisions (triggers, scry top, replacement order) are always
  "pick the next one" sequences. Write this down as the house style in
  `docs/guides/decision-api.md`.

**When:** `undo` and `done` legality with menace (F11). Domains with the first
card-naming or "any amount" card.

**Effort:** S–M.

---

### F17. The turn structure is fixed: no extra turns, phases or steps, no repeated cleanup, hard-coded land allowance

**Severity:** Low–Medium

**Blocks:** extra turns, additional combat phases (both appear in Standard),
"skip your next untap step", repeated cleanup (514.3a), extra land drops,
"play lands from the top of your library", day/night (game designation).

**Where:** `Engine#next_step!` does index arithmetic over `Steps::ORDER`, and
`begin_turn!(state.opponent(state.active))`. `Cleanup#priority? = false`.
`PlayLand::LANDS_PER_TURN = 1`.

**Problem:** The next step and the next turn are computed, not stored. The
next step is index arithmetic over a frozen `ORDER`, and the next turn always
goes to `opponent(active)`. An effect that adds or skips a turn, phase or step
has nothing to change. Cleanup can never give priority, so triggers that
happen during cleanup are lost.

**Recommendation:** Add `state.turn_queue` (upcoming turns: player and
modifiers; default alternation) and `state.step_queue` (built from
`Steps::ORDER` at turn start; effects insert `beginning_of_combat…end_of_combat`
copies or remove steps). `next_step!` pops the queue. Cleanup: after the
discard and the end of effects, if SBAs or triggers occurred, give priority
and push another cleanup (514.3a). Land allowance =
`1 + Rules.query(:extra_land_plays)`.

**When:** Cleanup repeat with triggers (F5). Queues before the first
extra-turn or extra-combat card.

**Effort:** S.

---

### F18. The docs describe capabilities the code doesn't have

**Severity:** Low (but it multiplies the cost of other findings, because
agents read docs first)

**Blocks:** nothing directly. It makes every mechanic an agent adds more
likely to be built against a seam that doesn't exist.

**Where:**
- `engine/characteristics.rb` header: "Power/toughness are computed through
  the layer-7 pipeline … stages … slot into their layer without touching
  callers". In reality it's a single `kind == "pump"` loop, and other
  characteristics bypass it (F2).
- ARCHITECTURE §5: "Events … feed … triggered abilities later". The engine
  never reads events (F5).
- DESIGN §2 lists triggers, conditions, amounts, continuous effects and
  replacements as primitive kinds. None exist (F8).
- ARCHITECTURE §2: "No Ruby call stack ever holds game progress". Not true
  during resolution (F1).

**Problem:** An agent that trusts these sentences will build on things that
aren't there. For example, it will add a P/T effect "into its layer" or
expect triggers to fire from events. The result is code that passes its own
tests but bypasses the real rules path.

**Recommendation:** Mark each of these "planned — see
docs/reviews/future-proofness.md F<n>". Add the `definition(` guardrail spec
(F2) and an architecture spec asserting that `State` has no process fields
except `frames` (F1), so the structural rules are enforced, not just
documented.

**When:** Now.

**Effort:** S.

---

## 3. Recommended build order (Standard-first)

Each phase lists what it unlocks. Phases 0–2 are mostly refactors with no
behaviour change, so they are cheap while the code is small and the test
suite is green.

### Phase 0: cheap guardrails (now, in parallel; S each)
- F12.1 field-table `GameObject`/`PlayerState` (old snapshots load with
  defaults).
- F14 `format` key + `to_data` canonical ability form.
- F15.2 `engine_version` + `catalog_digest` in snapshots; F15.4 kind-checked
  replay.
- F18 doc corrections + `definition(` guardrail spec.
- F8: swap `integer_param` → `amount_param` (integers only for now).

### Phase 1: structural core (before any more M2 features)
1. **F1 frames.** Move `casting` and `combat_damage` into frames; rewrite
   `resolve_top!` and SBAs as frames.
2. **F2 `chars(obj)`** with zero effects (pure refactor; whole-board compute
   + epoch cache).
3. **F3 ability refs** (option shape change; do it before external consumers
   exist).
4. **F6 propose/execute split** for `move!`, damage, life, draw and counters
   (no replacements yet, just the seam).

### Phase 2: M2 card expressiveness (the bulk of Standard instants, sorceries and ETB creatures)
5. **F7** parameterized filters + target specs (count, min, distinct) +
   `targetable?`.
6. **F8** amounts, conditions, `may`/`if`/`unless`, modes on the ability,
   `turn_stats`.
7. **F9** cast stages + checkpoint cancel + cost choices (sacrifice, discard,
   pay life) + X + kicker/additional costs.
8. Choice effects on frames: scry, surveil, mill, discard, search, "choose a
   color", sacrifice-a-creature.
9. **F12.2** tokens via the catalog (presets: Treasure, Clue, Food, Blood,
   Map) + SBA 704.5d.

### Phase 3: M2 triggers
10. **F5** trigger primitives, watcher, LKI, batches, APNAP ordering, trigger
    targeting, intervening-if, delayed and reflexive triggers, cleanup repeat
    (F17). Includes ETB, dies, attacks, upkeep/end step, cast and landfall.

### Phase 4: evergreen combat keywords (pulled forward from M4)
11. **F11** rules-query hooks; flying, reach, vigilance, menace (+ F16
    undo/`done` legality), defender, first/double strike step, trample with
    lethal/deathtouch assignment, deathtouch SBA flag, lifelink in the damage
    event, indestructible, hexproof; legend rule (supertype `legendary` + SBA
    frame).
12. Ward (needs F5 + F9 "unless pays").

### Phase 5: Standard mana bases (pulled forward from M3)
13. **F10** mana symbol lists + pool units + `any_color`/`one_of` produce
    (mana-ability choice frame); pain lands (pay life).
14. **F6 subset:** self-ETB replacements, "enters tapped (unless …)" and
    "enters with counters". This unlocks most Standard dual lands and many
    creatures without the full 616 machinery.

### Phase 6: M3 continuous effects
15. **F4** layer engine with stored and static effects, op primitives, CDAs,
    dependency sort, durations (`until_your_next_turn`, `for as long as`).
    Anthems, lords, "can't" statics (via F11 hooks), cost modification
    (F9 TotalCost stage), P/T setting versus modifying, "loses all
    abilities".
16. **F6 full:** "instead" replacements, prevention shields, 616.1 ordering
    decision, regenerate.
17. Counter registry (F12.4: +1/+1 and -1/-1 annihilation, keyword counters,
    shield, stun, lore); Auras and Equipment (`status.attached_to`, enchant
    and equip, 704.5m/n, attach timestamps); **Vehicles/crew** (layer 4 + tap
    cost choices).

### Phase 7: multi-face and frames (M4)
18. **F13** `faces`/`layout`: MDFC (land backs first), Adventure (cast
    permission from exile), transform; Sagas; Rooms; Classes/Cases; battles.
19. Cast permissions beyond hand (F9): flashback, impulse "may play this
    turn", plot.
20. Copy (707) as a layer-1 op; token copies; clones ("enters as a copy" via
    616.1c).

### Phase 8: long tail (M5)
21. F17 queues (extra turns and combats), F16 open domains (card naming),
    protection in full (DEBT), control change, planeswalker emblems (command
    zone), player counters (energy, rad) and designations (speed and the
    like), face-down mechanics (disguise, cloak).

**Critical path:** F1 → F2/F3 → F5 → F11. Everything in Phase 2 can run in
parallel with F5 once Phase 1 is done. F10 and the F6 subset can run in
parallel with Phase 4.
