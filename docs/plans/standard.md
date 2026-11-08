# Program: every Standard set imported, implemented and verified

**Goal.** For each Standard-legal set that stays legal past the next rotation, newest first:
1. Import every card into `lib/enjine/sets/<code>.json` (`script/convert_set.rb`).
2. Implement every mechanic the set needs, until `unsupported` is empty.
3. Play observed sample games with random decks built from the set
   (`Enjine::DeckBuilder` + `Enjine::RulesMonitor`), with zero rules findings and
   every card cast or activated at least once.
4. Mark the set **verified** in the README.

The deck builder reads the same set files (`sets=<code>`, `sets=standard`).

## Definition of "verified"

A set is verified when all of the following hold:
- `script/convert_set.rb <code>` reports **0 unsupported** cards.
- Every new mechanic has unit, integration and e2e specs (see
  `docs/guides/adding-a-mechanic.md`), and `bundle exec rake` is green.
- `script/observe_games.rb` runs at least 20 games with random 1-, 2- and 3-color
  decks from the set, alone and mixed with already verified sets. It finishes with
  **0 RulesMonitor findings** and a cast/activation for **every card** in the
  set; cards the random agent can't reach get a scripted scenario spec instead.
- The fuzzer (`rake fuzz` with invariants, rules monitor and export/import
  round-trips) passes on decks from the set.

## Sets, in work order

Release dates and rotation years are from Wizards' published schedule as
summarized at draftsim.com/mtg-standard-rotation (retrieved 2026-11-08). From 2027,
rotation happens at the first set release of the year. Legal-until dates for 2028
and later are **estimates** (January 1 of the rotation year) until that year's
first release is dated, and are marked `standard_legal_until_estimated: true` in
the set files.

| # | Set | Released | Leaves Standard | Status |
| ---: | --- | --- | --- | --- |
| 1 | Star Trek | 2026-11-13 | 2029 (est.) | in progress: 79/311 cards |
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | not started |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | not started |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | not started |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | not started |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | imported: 26/195 cards |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | not started |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | not started |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | not started |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | not started |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | not started |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | not started |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | not started |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | not started |

**Out of scope:** sets that are no longer Standard-legal, or that rotate out at the
next announced rotation, are not imported. On 2027-02-05 Wilds of Eldraine, The
Lost Caverns of Ixalan, Murders at Karlov Manor, Outlaws of Thunder Junction,
Bloomburrow and Duskmourn leave Standard, so they're skipped (the maintainer
decided this on 2026-11-08). When a new set releases, add it at the top. When a
rotation is announced, drop the rotating sets from this table and stop shipping
their set files.

**Every set file records when it stops being Standard:** `standard_legal_until`
(ISO date, the first day the set is no longer legal) and
`standard_legal_until_estimated` (true until Wizards announces the exact date).
`Sets.standard_legal(on: date)` and the deck builder's `sets=standard` use those
fields, so a set drops out of generated decks automatically on that date.

## How the work compounds

Most mechanics are shared across sets: triggered abilities, conditions, tokens,
evergreen keywords, the layer system, replacement effects, modal spells and
library manipulation. Star Trek pays for most of that infrastructure. Each later
set mostly adds its named mechanics plus long-tail effects. Track per set:
converted / total, and the top missing capabilities from the converter output.

## Card data rules

- **Structured data only.** Never store oracle or flavor text. Translations
  describe what a card does in Enjine primitives.
- **Printing identifier:** set code + collector number (`"printing": {"set", "number"}`).
  It's vendor-neutral; Scryfall is only the current converter source.
- **Card identity across sets:** a card's name is unique in Magic. A reprint in a
  later set must produce an identical definition, and the catalog raises
  `CatalogConflict` if two set files disagree.

## Rules version

The engine is pinned to the 2026-09-25 CR. Re-pin to the current CR (2026-11-06
or newer) before implementing Star Trek's Assimilate, which is defined only in
the newer document. Re-check every cited rule number against the renumbering
table in docs/MECHANICS_COVERAGE.md.
