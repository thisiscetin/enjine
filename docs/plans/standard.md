# Program: every Standard mechanic implemented

**Goal.** The engine supports every mechanic used by cards of the Standard-legal
sets that stay legal past the next rotation, newest set first. **Cards are written
by hand** in the [card DSL](../guides/card-data-format.md). The engine never reads
card text, and the repository ships no real card data. Set files hold only
metadata (name, release date, `standard_legal_until`) and an empty `cards` list
for cards you author.

For each set:
1. List the mechanics its cards need (keywords, keyword actions, set mechanics,
   ability and effect shapes) and compare that list with `SUPPORTED.md`.
2. Implement each missing mechanic as a primitive, cite its Comprehensive Rules
   numbers, and test it at every level with **invented** cards (unit, integration,
   and fuzz through `lib/enjine/card_pool/core.json`).
3. Mark the set's mechanics **supported** in the table below.

## Definition of "supported"

A set's mechanics are supported when:
- every mechanic it uses is listed in `SUPPORTED.md`, or is expressible with
  listed primitives, and is documented in `docs/guides/card-data-format.md`;
- every new mechanic has unit and integration specs plus at least one invented
  fuzz card, and `bundle exec rake` is green;
- `rake fuzz` (invariants, rules monitor, export/import round-trips) passes.

## Sets, in work order

Release dates and rotation years are from Wizards' published schedule as
summarized at draftsim.com/mtg-standard-rotation (retrieved 2026-11-08). From 2027,
rotation happens at the first set release of the year. Legal-until dates for 2028
and later are **estimates** (January 1 of the rotation year) until that year's
first release is dated, and are marked `standard_legal_until_estimated: true` in
the set files.

| # | Set | Released | Leaves Standard | Status |
| ---: | --- | --- | --- | --- |
| 1 | Star Trek | 2026-11-13 | 2029 (est.) | in progress |
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | not started |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | not started |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | not started |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | not started |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | partial |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | not started |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | not started |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | not started |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | not started |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | not started |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | not started |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | not started |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | not started |

**Out of scope:** sets that are no longer Standard-legal, or that rotate out at the
next announced rotation, are out of scope. On 2027-02-05 Wilds of Eldraine, The
Lost Caverns of Ixalan, Murders at Karlov Manor, Outlaws of Thunder Junction,
Bloomburrow and Duskmourn leave Standard, so they're skipped (the maintainer
decided this on 2026-11-08). When a new set releases, add it at the top. When a
rotation is announced, drop the rotating sets from this table and their set files.

**Every set file records when it stops being Standard:** `standard_legal_until`
(ISO date, the first day the set is no longer legal) and
`standard_legal_until_estimated` (true until Wizards announces the exact date).
`Sets.standard_legal(on: date)` and the deck builder's `sets=standard` use those
fields, so a set drops out of generated decks automatically on that date.

## Card data rules

- Cards are authored by hand in the DSL. Nothing in the repository derives card
  data from rules text.
- **Printing identifier:** set code + collector number (`"printing": {"set", "number"}`),
  which is vendor-neutral.
- **Card identity across sets:** a card's name is unique in Magic. The catalog
  raises `CatalogConflict` if two definitions with one name disagree.

## Rules version

The engine is pinned to the 2026-11-06 CR (`Enjine::RULES_VERSION`). When a newer
CR comes out, re-pin: diff the section headings, renumber what moved, and run
`bundle exec rake "cr_citations[path/to/cr.txt]"` to check that every cited rule
number exists in the new text (see docs/MECHANICS_COVERAGE.md).
