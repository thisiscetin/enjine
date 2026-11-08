# Design review: consolidated verdict and action plan

Three independent reviews of the code at commit `9247de3` (2026-11-08):

| Review | Score | File |
| --- | --- | --- |
| Elegance and code design | 7/10 | [elegance.md](elegance.md) (findings E1–E15) |
| Performance | ~6x headroom | [performance.md](performance.md) (findings P1–P10) |
| Future-proofness | 5/10 now, ~8/10 after four core refactors | [future-proofness.md](future-proofness.md) (findings F1–F18, build order) |

**This file is the work queue.** The three reviews hold the evidence and the detailed
recommendations. Read the referenced finding before implementing it.

## Verdict

The foundations are right and should be kept. Every review independently called
these load-bearing:
- the explicit, serializable state machine;
- atomic decisions with all-or-nothing `apply`;
- snapshot validation used as the fuzz invariant;
- CR 400.7 object identity;
- the primitive registry, with docs generated from it.

Three problems need fixing before more features go on top:

1. **Two crash bugs and one hot-path bug.** E1 and E2 are crashes. E3 (= P1) is a
   per-lookup Unicode slug that accounts for about 70% of runtime.
2. **The engine can't pause in the middle of a process (F1).** Resolution and
   state-based actions run to completion in one go. That blocks scry, search,
   "you may", trigger ordering and the legend rule. The casting and combat-damage
   contexts are already ad-hoc versions of the general fix: a stack of serializable
   frames.
3. **"Data-driven" stops at the edge of the engine (E4–E6, E10, F2, F3, F11).**
   Types, keywords, costs and continuous effects are registered as data, but the
   engine interprets them through hardcoded `type?`/`kind ==` branches. It also
   reads characteristics from the printed card instead of computing them. Layers,
   granted abilities, Vehicles and triggers can't be added cleanly until a
   `chars(obj)` seam and stable ability references exist.

Performance isn't a design problem: P1, P2, P5 and P6 are S/M patches worth about
5.8x (9.6k → 55.8k decisions/s, measured, no YJIT). Determinism digests are
unchanged.

## Work queue

Work top to bottom. One finding (or one tightly coupled group) per commit. Each
commit must keep `bundle exec rake` green (specs, coverage gate, docs drift,
RuboCop) and keep `rake fuzz` passing. Cite the finding id in the commit message.

### Tier 0: bugs (do first, S each)

| # | Finding | Action |
| --- | --- | --- |
| 0.1 | **E1** | `Game#apply` on a freshly imported game raises `NoMethodError` (`@version` is nil). Initialize `@version = 0` in `Game#initialize`, and add a regression spec. |
| 0.2 | **E2** | `history_for(opponent)` crashes after `concede`. Handle `"concede"` in `HistoryEntry#for_viewer` **without** registering it as a decision kind, since snapshot import must still reject `pending.kind == "concede"`. Add a regression spec. |
| 0.3 | **E13** | Narrow `Game.import`'s rescue to `Snapshot.load` and `HistoryEntry.from_h`, so engine bugs propagate. Make the `Game` doc honest: illegal submissions never mutate state. Optionally add `paranoid:` transactional submit. |

### Tier 1: performance quick wins (S/M; measured in performance.md)

| # | Finding | Action | Measured gain |
| --- | --- | --- | --- |
| 1.1 | **P1 = E3** | `Catalog#fetch`/`[]`/`include?`: exact-id lookup first, slug only on a miss. | 3.66x |
| 1.2 | **P5** | Precompute `CardDefinition` predicates (`creature?`, `land?`, `instant_speed?`, …) in `initialize`. | +9% |
| 1.3 | **P2** | Compute mana sources once per `options` call, not once per hand card or ability. | +39% |
| 1.4 | **P6** | Cheaper permanent state-based-action check (skip non-creature/non-planeswalker; compute toughness once). | +5% |
| 1.5 | **P3** | Hand-written `State#fork` (25 µs vs 258 µs for Marshal). Use it in `transaction`, and expose it as `Game#fork` for search-based agents. **Must copy every State field**; add a spec that `fork.to_h == to_h` after a fuzzed game. Coordinate with Tier 3.1 (frames must be copied too). | 10x on fork |
| 1.6 | **P4** | `submit_index(i)` and `history: false` mode for training loops. | +10% |
| 1.7 | **P7** | Faster export/import/validate (the fuzzer bottleneck). | see P7 |
| 1.8 | **P9 + perf harness** | Add the benchmark harness from performance.md §"Benchmark harness to add" as `rake bench`. Not a CI gate. | — |
| 1.9 | **P8** (environment) | Document in the README that YJIT needs Ruby built with `rustc` available. | est. 1.5–2.5x |

### Tier 2: cheap guardrails (future-proofness Phase 0; S each)

| # | Finding | Action |
| --- | --- | --- |
| 2.1 | **F14** | Add a `"format"` version key to card data plus a canonical `to_data` form for abilities. |
| 2.2 | **F15** | Add `engine_version` and `catalog_digest` to snapshots; kind-checked replay. |
| 2.3 | **F12.1 + E9** | Make `GameObject`/`PlayerState` field tables with defaults, built in one place, so old snapshots load and the four hand-built constructors become one. |
| 2.4 | **F8** | Replace `integer_param` with `amount_param` (integers only for now: the seam for X and "number of …"). |
| 2.5 | **F18** | Fix docs that overstate capabilities. Add a guardrail spec that counts direct `definition(` reads in the engine. |
| 2.6 | **E14** | Add a fuzz assertion: no object id from a zone hidden to `p` appears in `view_for(p)` or `history_for(p)`. |
| 2.7 | **E8, E12, E15** | Consistency pass: one spelling of "kind", one player identity type at API boundaries, the small duplications. |

### Tier 3: structural core (future-proofness Phase 1; before any more M2 features)

Do these in order. Each one is a refactor with **no behavior change**: the existing
171 specs plus the fuzzer are the safety net.

| # | Finding | Action | Absorbs |
| --- | --- | --- | --- |
| 3.1 | **F1** | A serializable **frame stack** on `State`. Move `casting` and `combat_damage` into frames, and rewrite `resolve_top!` and the SBA loop as frames that can suspend for a decision. | E7 (one mana-ability path), parts of E11 |
| 3.2 | **F2** | `chars(obj)`: one computed-characteristics entry point (types, keywords, abilities, P/T, colors) with whole-board compute and an epoch cache. Zero effects at first, as a pure refactor; migrate all printed-definition reads to it. | E4 (types/keywords via composition), E10 (effects interpret themselves), F4 groundwork |
| 3.3 | **F3** | Stable ability references instead of list indexes in options and stack objects. This **changes the public option shape**, so do it now, before external consumers exist. | — |
| 3.4 | **F6** | Propose/execute split for `move!`, damage, life, draw and counters. No replacements yet; this only creates the seam replacement and prevention effects need. | E6 (costs as one list) |
| 3.5 | **E5** | An explicit primitive contract per category (one schema used both for validation and for docs). | — |
| 3.6 | **E11** | Split the ~70-method `Engine` surface along the module seams created above; move rules logic out of Decision classes into the engine consistently. | — |

### Tier 4: features (future-proofness Phases 2–8, Standard-first)

Follow the build order in [future-proofness.md](future-proofness.md):
- **Phase 2:** card expressiveness: F7 parameterized filters, F8 amounts/conditions/durations, F9 casting extensions, F10 mana.
- **Phase 3:** triggers and last-known information (F5).
- **Phase 4:** evergreen combat keywords (F11).
- **Phase 5:** Standard mana bases.
- **Phase 6:** layers and static abilities (F4).
- **Phase 7:** multi-face cards (F13).
- **Phase 8:** the long tail (F16, F17).

Every new mechanic follows [docs/guides/adding-a-mechanic.md](../guides/adding-a-mechanic.md):
unit, integration and e2e tests, a card in the core pool, and `rake docs`.

## Decisions reserved for the maintainer

An implementing agent should **stop and ask** before doing any of these:

1. **F3 option shape change** (`ability: 0` → a stable reference). This is a breaking
   API change. The recommendation is to do it now, but the maintainer should confirm.
2. **E14 opaque object ids** (`"o17"` instead of `"lightning_bolt#17"`). This is
   recommended only when face-down cards arrive; until then, keep the readable ids
   and the Tier 2.6 assertion.
3. **The cast/activate affordability filter.** Options appear only when available
   mana ≥ mana value. Keep this filter, or offer every timing-legal cast and let
   payment fail?
4. **The rules version re-pin** to the 2026-11-06 CR (it renumbers 7xx; see
   docs/MECHANICS_COVERAGE.md), at the start of Tier 4.

## Conflicts and overlaps the reviews flagged

- **P3 `State#fork` vs F1 frames.** `fork` must deep-copy the frame stack. Implement
  1.5 with a field-driven copier, built on 2.3's field tables, so new fields are
  never forgotten.
- **E3 and P1 are the same finding.** E9 and F12.1 overlap and are merged as 2.3.
  E4/E10 overlap F2/F4 and are merged as 3.2.
- **Performance vs structure.** 3.2's epoch cache must keep the Tier 1 numbers. Rerun
  `rake bench` before and after each Tier 3 item, and record the numbers in the commit message.
