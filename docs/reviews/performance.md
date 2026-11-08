# Enjine performance review

Scope: the cost of a decision, its allocations, legal-option computation, fork/export/import and memory per game, with RL training (millions of games) in mind.
Code measured: `lib/` as of commit `9247de3` (2026-11-08), copied to a scratch snapshot so it stayed fixed during measurement.
Machine: Apple M4 (4P+6E), Ruby 4.0.1 **without YJIT** (no YJIT/ZJIT build exists on this machine; rustc is not installed).
Workload: `gruul_beats` vs `azorius_walkers`, `Agents::Random` (current version, `cancel_rate: 0.02`), seeds 1..40, about 1,000–1,150 decisions per game. This baseline (9.6k decisions/s, 8.9 games/s) is higher than the ~8.9k / ~7 games/s quoted in the brief because the agent version and seeds differ (the current agent rarely cancels, so games are shorter), not because of a different machine.
Prototype patches and scripts live in `/private/tmp/claude-501/-Users-m-Products-enjine/309bd88e-b728-4a46-a9a1-177473ee06d5/scratchpad/perf/`, a session scratch directory that may not persist; `scratchpad/perf/...` below refers to it. Every prototype below was checked for determinism. Final-state and decision-log SHA-256 digests for seeds 3, 7 and 11 are identical to the baseline. With the engine prototypes for P1, P2, P5 and P6 plus a `State#fork`-based transaction (P3) loaded together, the full suite (171 examples) passes. P4 (`submit_index`, `history: false`) was validated only by the seed-7 final-state digest, not by the suite. A 30-game fuzz run with invariants and `roundtrip_every: 50` also passes.

## 1. Verdict

The engine is about **6x slower than it needs to be**. One bug causes most of that: every card-definition lookup runs a Unicode-normalising slug function. The rest is redundant battlefield scans inside legal-option computation. The design itself (explicit state machine, id-keyed plain structs, events) is not the bottleneck. Once the hotspots are fixed, the profile is flat interpreter overhead with no single frame above about 8% self time.

| Configuration (single thread, no YJIT) | games/s | decisions/s | µs/decision | allocs/decision | GC share |
|---|---:|---:|---:|---:|---:|
| **Baseline** (commit 9247de3) | 8.9 | 9,600 | 104 | 682 | 6.8% |
| + P1 catalog exact-id lookup | 32.4 | 35,100 | 28.5 | 150 | 7.6% |
| + P5 precomputed definition predicates | 35.2 | 38,200 | 26.2 | 150 | 7.9% |
| + P2 mana sources computed once per options call | 49.0 | 53,100 | 18.8 | 64 | 4.3% |
| + P6 cheaper permanent SBA check | **51.4** | **55,800** | **17.9** | **58** | 3.7% |
| + P4 submit-by-index and `history: false` | 56.7 | 61,500 | 16.2 | 51 | — |
| P1+P2+P5+P6 on 8 processes (`fork`) | **280** aggregate | ~300k | — | — | — |

**Realistic target:**
- **Measured, pure Ruby, no YJIT:** about 55–60k decisions/s, or 50–55 random games/s per core. That is a **5.8–6.4x** gain from S/M-effort changes. On this 10-core M4 that gives about **280 games/s** across 8 processes (measured scaling: 1→52, 4→190, 8→280, 10→284 games/s). One million random games would take about 1 hour, against 31 hours today on one core.
- **Estimated, not measured:** a YJIT build of Ruby should add roughly another 1.5–2.5x per core. The post-fix profile is dominated by method dispatch, `Hash#fetch`, `Array#each`, `flat_map` and `Data#initialize`, which YJIT handles well. That puts the expected range at about 90–140k decisions/s per core.
- **Native extension:** not justified yet. Revisit only if the measured YJIT numbers fall short of what the trainer needs. The 6x below is free.

## 2. Findings

### P1. `Catalog#fetch` slugifies every lookup (Unicode NFKD + 4 regex passes)
- **Impact:** **3.66x** throughput (9.6k → 35.1k decisions/s). Allocations per decision fall 682 → 150 (−78%). In memory_profiler over 5 games, `card_definition.rb:20` accounts for **103 MB of 142 MB** allocated.
- **Where:** `lib/enjine/catalog.rb:32-37` (`fetch`, `[]`, `include?` all call `CardDefinition.slug(ref)`). The hot caller is `lib/enjine/engine.rb:27` (`def definition(object) = catalog.fetch(object.card)`), which runs dozens of times per decision. `slug` itself is at `lib/enjine/card_definition.rb:19-21`. A second caller is `lib/enjine/snapshot.rb:132` (`catalog.include?` per object during validation).
- **Evidence:** wall profile with GC disabled, 20 games. `CardDefinition.slug` is **69.7%** of total time, `String#gsub` alone 56.6%, `UnicodeNormalize.normalize` 32.1%. In cpu mode stackprof reported 88% "GC", which is a sampling artefact: `GC.stat(:time)` shows only 6.8% real GC time. Most of that GC was still slug garbage.
- **Recommendation:** `object.card` is always a canonical id, because `create_object` receives decklist ids. So:
  1. Add an exact lookup, `Catalog#definition(id) = @definitions.fetch(id)`, and use it in `Engine#definition`, `Snapshot.validate_object`, `cli/text.rb` and anything else holding an object's `card`.
  2. Keep the name-tolerant API for user input (`Deck` calls `@catalog.include?(card)` with display names), but give it a fast path: `@definitions[ref] || @definitions[CardDefinition.slug(ref)]`. Do the same for `[]` and `include?`. The prototype used only this fast path, which delivered the whole 3.66x.
  3. Optionally memoise `slug` results in a frozen-per-catalog Hash.
- **Risk:** essentially none. An exact-id hit returns the same definition the slug path would, because ids are already slugs. Digests are identical.
- **Effort:** S (about 5 lines).

### P2. Legal-option computation rescans the battlefield for mana sources once per hand card and once per ability
- **Impact:** **+39%** on top of P1+P5 (38.2k → 53.1k decisions/s). Allocations per decision fall 150 → 64.
- **Where:**
  - `lib/enjine/actions/cast.rb:12-14`: `castable?` per hand card.
  - `lib/enjine/engine/casting.rb:13-20`: `castable?` → `affordable?` (line 43) → `mana_sources` (line 51). That scans the whole battlefield, all abilities, and runs `activatable?` → `Tap#payable?` → `summoning_sick_for_tap?` each time.
  - `lib/enjine/actions/cast.rb:27-36`: `Activate.options` calls `activatable?` for every ability index of every permanent, including mana abilities. That in turn calls `affordable?` and rescans.
  - `lib/enjine/actions/activate_mana_ability.rb:12-21` performs the same scan a third time.
- **Evidence:**
  - Priority decisions are **85.6%** of all decisions (avg 2.5 options, battlefield avg 16 objects).
  - After P1: `Decisions::Priority.options` is 54% of time, made up of `Cast.options` 22.7%, `ActivateManaAbility.options` 14.9%, `Activate.options` 13.9% and `mana_sources` 13.0%.
  - Top allocation sites after P1: `activate_mana_ability.rb:17` 6.2 MB, `cast.rb:32` 6.2 MB, `casting.rb:58` 5.0 MB, all from `each_with_index.filter_map` enumerators.
- **Recommendation:**
  - Compute the controller's mana-source list (`[[id, ability_index], ...]`) **once per `Engine#options` call** and memoise it in an ivar that `Engine#options` (`engine.rb:348`) resets on entry and exit (`ensure`).
  - `mana_sources(index, excluded)` becomes `list.reject { it[0] == excluded }`.
  - `affordable?` uses `list.size`, or `list.count { it[0] != excluded }` when there is an exclusion.
  - `ActivateManaAbility.options` maps the same list into option hashes.
  - `Activate.options` iterates only precomputed activated/loyalty ability indices (see P5), not every ability.
  - Use plain `each` with `<<` instead of `each_with_index.filter_map` / `flat_map` to avoid Enumerator allocation.
  - Prototype: `scratchpad/perf/p3_options.rb`, about 40 lines.
- **Risk:** low. The memo must never outlive one `options` call, because any mutation (a tap, or a zone change) invalidates it. The prototype clears the memo only in `Engine#options`, and `all_mana_sources` fills it lazily. If any future caller reaches `affordable?`, `mana_sources` or `payment_sources` outside an `options` call, the memo would be filled there and go stale after the next tap or zone change. Implement it as an explicit per-call context, or set an "inside options" flag and have `all_mana_sources` skip the cache when the flag is unset. Today every caller runs inside `options`. Option order is unchanged; digests are identical.
- **Effort:** S–M.

### P3. Transaction/fork uses a `Marshal` round trip: 258 µs, about 14 decisions' worth; a hand-written copy takes 25 µs
- **Impact:** **10.3x** faster state copy (mid-game, turn 15, 120 objects: 258 µs → 25 µs). This does not affect random self-play, which never forks, but it dominates any search-based RL (MCTS, lookahead, `apply` per step). It also halves the cost of `apply` on short option lists.
- **Where:** `lib/enjine/game.rb:159-172` (`transaction`: `Marshal.dump(state)`, with `Marshal.load` on failure). There is no public `Game#fork`/`dup` API, so callers would have to use `export`/`import` (2.5 ms total, see P7).
- **Evidence (benchmark-ips, mid-game state):**
  - `Marshal.dump(state)` 119 µs. Of that, `Marshal.dump(state.objects)` alone is 107 µs; dumping Structs is slow.
  - dump + load 258 µs.
  - Prototype `State#fork` 25.0 µs; its `to_h` equals the original's, and mutating the copy leaves the original unchanged.
  - The full spec suite passes with `transaction` rewritten to use `State#fork`.
- **Recommendation:**
  - Add `State#fork`. It `dup`s the State and each PlayerState (and dups their `library`/`hand`/`graveyard` arrays and `mana_pool`). It copies `objects` with `transform_values`, dup'ing each GameObject and its `counters` and `targets`. It dups `battlefield`, `stack`, `exile` and `blockers`, and copies `attackers` with `transform_values(&:dup)`. It creates a fresh `Rng.new(rng.state)` and `deep_dup`s `effects`, `casting` and `combat_damage`. Decklists and seed stay shared, since they are frozen.
  - Use it in `Game#transaction`.
  - Expose `Game#fork(history: false)`, which returns a new Game sharing the catalog with a forked state and an empty or shared-frozen history.
  - Freeze object id strings at creation (`engine.rb:211`, `-"#{card}##{n}"`) so sharing them between forks is provably safe.
  - Prototype: `scratchpad/perf/p5_fork.rb`.
- **Risk:** medium. A future State field that is a mutable container must be added to `fork`, otherwise forks alias each other. Mitigate with a spec that forks, mutates every container in the copy, and asserts the original's `to_h` is unchanged. Also assert `fork.to_h == state.to_h` inside the fuzzer. Determinism is unaffected; the RNG state is an Integer.
- **Effort:** S–M.

### P4. Observation, history and option-submission overhead around each decision
- **Impact:**
  - `submit_index` (skipping `normalize` and `options.include?`, `game.rb:93-98`, `178-182`): **+3.5%**.
  - Additionally not building `HistoryEntry`s: **+6.5%**. The cumulative 55.8k → 61.5k decisions/s is measured.
  - Memory: history is **506 KB of heap per finished game, versus 67 KB for the state** (7,583 vs 546 objects), so 88% of a game's footprint.
  - `export` is 321 KB of JSON per finished game (state alone about 32 KB at turn 15).
  - `view_for(player)` costs **45 µs**, 2.5x a whole decision; `view_for(:observer)` costs 169 µs.
- **Where:**
  - `lib/enjine/game.rb:147-157` (`record`: `[state.turn, state.step&.to_s]` allocates a String per decision; `HistoryEntry` plus `@buffer.dup` per decision).
  - `lib/enjine/game.rb:74-84` (`pending_decision`: `Decision` Data plus `pending.except` per decision).
  - `lib/enjine/view.rb:90`: `pending_view` calls `engine.options` directly, which **bypasses `Game#pending_decision`'s cache**. An RL loop doing `view_for` + `pending_decision` therefore computes legal options twice per step.
- **Evidence:**
  - memory_profiler after P1/P2: the top allocation sites include `game.rb:181` (normalize, 12.6k objects per 5 games), `game.rb:150/152/153` (record, about 25k) and `game.rb:80/82` (Decision, about 15k).
  - Events average 2.1 per decision.
- **Recommendation:**
  1. Add `Game#submit_index(i)`, which takes the i-th option of the cached decision with no normalisation or `include?`. This is the natural API for a policy head over legal actions. Keep `submit(hash)` for humans.
  2. Add `Setup#new_game(seed:, history: true)`. With `history: false`, `record` still buffers events for subscribers, but no `HistoryEntry` is stored. `decision_log` can be kept as a compact `Array` of option indices (2–4 bytes each) so replay and `seed + log` still work.
  3. `View.pending_view` should take the options from `Game#pending_decision` (pass the decision in) rather than calling `engine.options`.
  4. Use `state.step&.name` (frozen, no allocation) instead of `to_s` in `record` and in `StepBegan` (`engine.rb:142`).
  5. For RL observations, provide a lighter `observation_for(player)` that returns ids and integers only, with no `type_line` or `rules_text` strings (those are static per definition and can be looked up once by the trainer). `View.object_view` currently rebuilds `type_line` (string joins) for every object on every call (`card_definition.rb:74-78`); at minimum memoise `type_line` on the frozen definition.
- **Risk:** low. With history disabled, `history_for` must raise or return `[]` explicitly. Export with history disabled must still round-trip the state (it does; state and history are separate keys).
- **Effort:** S (1, 3, 4), M (2, 5).

### P5. `CardDefinition` predicates recompute on every call
- **Impact:** **+8.7%** (35.1k → 38.2k decisions/s with P1). It also enables P2's index lists.
- **Where:** `lib/enjine/card_definition.rb:56-72`:
  - `type?` → `@types.include?(type.to_sym)`; `land?`, `creature?` and `planeswalker?` go through it.
  - `spell_ability` is a linear `find` per call.
  - `instant_speed?` → `@type_modules.any?` plus `keyword?`.
  - `permanent?` → `any?`.
- **Evidence:** after P1, `CardDefinition#type?` is 6.1% of total and `creature?` 4.1%. These are called from SBA, combat, the mana-source scan and View for every battlefield object at every priority point.
- **Recommendation:**
  - Compute `@creature`, `@land`, `@planeswalker`, `@permanent`, `@castable`, `@instant_speed`, `@haste`, `@spell_ability`, `@mana_ability_indices` and `@activated_ability_indices` in `initialize` **before** `validate_type_specific` runs, because validation uses the predicates and the object is frozen at the end.
  - Expose the predicates as readers.
  - Also precompute `Mana::Cost#mana_value` (`mana.rb:26` allocates `colored.values` on each call, 6.5k objects per 5 games).
  - Prototype: `scratchpad/perf/p2_flags.rb`.
- **Risk:** none. Definitions are immutable.
- **Effort:** S.

### P6. Permanent state-based-action check runs on every priority grant and computes toughness twice
- **Impact:** **+5%** (53.1k → 55.8k decisions/s); allocations per decision 64 → 58.
- **Where:** `lib/enjine/engine/damage.rb:54-65`, called from `give_priority!` (`engine.rb:177`) on every pass, which is 62% of all choices. For each battlefield object it calls `definition` up to three times and `toughness(obj)` twice. Each `toughness` call runs the full `power_toughness` pipeline (`characteristics.rb:16-28`), which scans `state.effects` and allocates two arrays. `filter_map` allocates even when nothing dies.
- **Evidence:** after P1, `check_permanent_state_based_actions!` is 16.1% of total time.
- **Recommendation:**
  - Look up `defn` once and branch on `creature?`/`planeswalker?`, so other permanents cost one lookup.
  - Compute toughness once.
  - When `state.effects.empty? && obj.counters.empty?`, use `defn.toughness.to_i` directly.
  - Allocate the `doomed` array lazily and return `false` without allocating.
  - Keep the current semantics (simultaneous moves, CR 704.3).
  - Do **not** add a "dirty flag" to skip the check entirely yet. It would be a bigger win, but every mutation path would have to set it, which is a correctness risk while the effect set is still growing.
  - Prototype: `scratchpad/perf/p4_sba.rb`.
- **Risk:** low. The fast path must be revisited when static/continuous P/T effects (layers 7a/7b) land: gate it on "no P/T-affecting effects or statics on the battlefield", not just `effects.empty?`.
- **Effort:** S.

### P7. Export, import and validation are slow and bottleneck the fuzzer
- **Impact:**
  - `Game.import` of a state-only mid-game snapshot takes **731 µs** (with history: 1.76 ms with P1, P2, P5 and P6, 2.05 ms at baseline).
  - `Snapshot.validate` takes **495 µs** at baseline and 272 µs after P1.
  - `Fuzz.run(invariants: true)` runs at **1,623 decisions/s** at baseline and 3,286 with P1, P2, P5 and P6, against 53,175 without invariants. The invariant check is a **16x** slowdown and dominates CI fuzz time.
- **Where:**
  - `lib/enjine/snapshot.rb:135`: `State::ZONES.map(&:to_s)` builds an array of 6 strings **per object**.
  - `snapshot.rb:129`: regex per object.
  - `snapshot.rb:69`: `deep_copy` = `Marshal.load(Marshal.dump(v))`, called **twice per object** in `build_object` (lines 64, 66) and 5 more times in `build`.
  - `snapshot.rb:233` (`deep_stringify`, 201 µs, rebuilds the whole tree even when keys are already strings).
  - `history.rb:7-11` (`HistoryEntry.from_h`, 727 µs for 344 entries).
  - `fuzz.rb:60` (`Snapshot.validate(game.state.to_h, …)` per decision; `state.to_h` alone is 48 µs).
- **Evidence:** stackprof of `validate`: `validate_object` 60% total, `Array#map` + `Symbol#to_s` 15.6%, `Regexp#match` 8%, `validate_zone_membership` 12.9%.
- **Recommendation:**
  - Add a `ZONE_NAMES = ZONES.map(&:to_s).freeze` constant.
  - Use the P1 exact-id lookup for `catalog.include?`.
  - Replace `deep_copy` with a recursive Hash/Array copy (JSON-shaped data only).
  - Skip `deep_stringify` when the input came from `JSON.parse`, which is already string-keyed.
  - In the fuzzer, validate only every N decisions by default, or validate the live structs directly without `to_h`.
  - For RL replay, recommend `seed + decision indices` over snapshots. Import is about 40 decisions' worth of time.
- **Risk:** low. Validation must stay exhaustive; these are constant-factor changes only.
- **Effort:** S–M.

### P8. Run on a YJIT-enabled Ruby (environment, not code)
- **Impact:** estimated 1.5–2.5x per core. **Not measured**: neither installed Ruby (4.0.1, 4.0.9) has YJIT, and rustc is missing.
- **Where:** environment. DESIGN.md §10 already says "Ruby 4.0.x with YJIT", but the dev machine does not match.
- **Evidence:** after P1, P2, P5 and P6 the top self frames are `Hash#fetch` 8.2%, `Engine#object` 7.5%, `Array#each` 6.0% and `Catalog#fetch` 5.7%, followed by a long tail of small methods (`sorcery_timing?`, `player`, `state`, `Data#initialize`). That is classic interpreter dispatch overhead, which is what YJIT removes.
- **Recommendation:** `brew install rust` and reinstall Ruby (`asdf install ruby 4.0.9` with `RUBY_CONFIGURE_OPTS=--enable-yjit`). Run training workers with `--yjit` (or `RUBY_YJIT_ENABLE=1`), and print `RubyVM::YJIT.enabled?` in the bench task. Re-measure before considering any native code.
- **Risk:** none for determinism. The engine uses integer arithmetic only and no hash-order-dependent randomness.
- **Effort:** S.

### P9. Scale out with processes
- **Impact (measured, with P1, P2, P5 and P6, `Process.fork` workers, 30 games each):** 1 → 52, 4 → 190, 8 → 280, 10 → 284 games/s (M4: 4 performance and 6 efficiency cores).
- **Where:** trainer side. Ractors are not viable today: the registries are mutable constants (`Decisions::KINDS`, `Actions::PRIORITY`/`BY_TYPE`, `Events::REGISTRY`), and `Setup`/`Catalog` hold non-shareable objects.
- **Recommendation:** document "one game loop per process, `Setup` built before fork so it is shared copy-on-write". Freezing the registries after load (`Enjine.finalize!`) would be a cheap step toward Ractor-shareability later.
- **Risk:** none.
- **Effort:** S (documentation).

### P10. Measured and not worth doing now
These are listed so nobody spends time on them prematurely.
- **Integer object ids instead of `"card#n"` strings:** string-key `Hash#fetch` takes about 40 ns against about 20 ns for `Array#[]`. An identity-keyed definition cache on the engine gave only +1.6% (within noise). The snapshot format change and loss of readability are not worth about 5%.
- **RNG bignums:** PCG32 multiplies into more than 62 bits, costing **7.3 allocations and 368 ns per `rand`**, about 2% of a random-agent decision. Fix only if rollouts become RNG-heavy. Use 32-bit limb arithmetic so values stay Fixnums, and check bit-exactness against the current generator.
- **`empty_mana_pools!` / `mana_value` / `Symbol#to_s` micro-allocations:** +1% combined. Fold them into P4/P5 while those files are open.
- **The agent:** `Agents::Random#choose` allocates `options - [CANCEL]` per decision. That is trainer-side and negligible.

## 3. Benchmark harness to add

The Rakefile's `bench`/`profile` tasks build **random decks** from the pool, so decision counts and results are not comparable between commits. Replace them with a fixed harness (the scratch scripts `run_patched.rb`, `fork.rb` and `mem.rb` in this review are its prototype):

- **`bench/decisions.rb`** (rake `bench`):
  - Fixed decks `gruul_beats` vs `azorius_walkers`, `Agents::Random.new(seed: s)`, seeds 1..40, one warm-up game, then `GC.start`.
  - Report games/s, decisions/s, µs/decision, `total_allocated_objects` per decision, `GC.stat(:time)` share, and `RubyVM::YJIT.enabled?`.
  - Print a **determinism digest**: SHA-256 of `decision_log + export` for seeds 3, 7 and 11. A perf PR must not change it unless it intends to change rules.
- **`bench/state_ops.rb`** (rake `bench:state`): reach a fixed mid-game position (seed 5, first priority at turn ≥ 15). Use benchmark-ips for:
  - `State#fork` (or `Marshal` until P3 lands)
  - `state.to_h`
  - `export`
  - `Game.import` (state only, and with history)
  - `Snapshot.validate`
  - `view_for(player)` and `view_for(:observer)`
  - uncached `engine.options`
  - `setup.new_game`
- **`bench/memory.rb`** (rake `bench:memory`): for 10 finished games, report the retained heap of state and of history (`ObjectSpace.reachable_objects_from` walk, excluding Catalog and CardDefinition), export JSON bytes, and `Marshal.dump(state)` bytes. Also run a memory_profiler top-20 allocation-sites report over 5 games.
- **`rake profile`:** use stackprof **`mode: :wall` with `GC.disable` around the run**. In cpu mode on Ruby 4.0, stackprof attributed 88% of samples to GC while real GC time was 6.8%, which hides the real hotspots.
- Keep it out of CI gates, as DESIGN.md says. Do commit a `bench/BASELINE.md` with the latest numbers and machine, and require PRs touching `engine/`, `actions/`, `decisions/` or `game.rb` to paste before/after rows.

Reference numbers to start that file (M4, Ruby 4.0.1 without YJIT, commit 9247de3): 8.9 games/s, 9,600 decisions/s, 682 allocs/decision. Mid-game Marshal fork 258 µs, import 731 µs, `view_for(player)` 140 µs (45 µs after P1). Per finished game: history 506 KB heap, state 67 KB, export 321 KB.
