# Plan: Star Trek (`trk`) fully verified

Goal: every card of the Star Trek expansion (Scryfall set `trk`, released
2026-11-13, 311 unique cards) is converted to Enjine card data, passes
validation, and is verified in play. Then the README lists `trk` as a
**verified set**.

Data goes in `lib/enjine/sets/trk.json`. It ships with the gem and isn't loaded
by default. It contains structured card data plus each card's **printing
identifier**: the set code and collector number printed on the card
(`"printing": {"set": "trk", "number": "12"}`). That identifier belongs to the
card, not to any database. Scryfall (`/cards/trk/12`), MTGJSON (set + `number`),
Gatherer and most price sites can all resolve it, so images and prices are one
lookup away without tying Enjine to a vendor. The file does **not** contain
oracle text. The legal-until date is estimated from the usual rotation pattern
and flagged as an estimate.

## Census: what the cards need

A pattern census over the oracle text (fetched from the Scryfall API on
2026-11-08; counts are approximate, and a card can appear in several rows):

| Capability | Cards | Status |
| --- | ---: | --- |
| conditions ("if", "unless", "as long as") | 112 | todo (F8) |
| legendary permanents (legend rule, 704.5j) | 104 | todo |
| triggered: enters the battlefield | 102 | todo (F5) |
| triggered: other "whenever" | 79 | todo (F5) |
| counters (+1/+1 and named counters) | 66 | done: any named counter; stun, shield, finality, keyword counters; enters-with and doubling replacements |
| tokens (create; Treasure, Food, Clue, creature tokens) | 61 | todo (F12) |
| X costs and variable amounts ("equal to", "for each") | 55 | todo (F8, F10) |
| exile | 53 | todo |
| sacrifice | 47 | todo |
| modal ("choose one") | 47 | todo (F9) |
| cast from graveyard/exile | 37 | todo (F9) |
| triggered: "at the beginning of" | 33 | todo (F5) |
| look at the top / scry / surveil | 30 | todo (frames) |
| static grants and anthems | 25 | todo (F4) |
| tap/untap effects | 23 | todo |
| discard | 20 | todo |
| bounce | 17 | todo |
| **Station** (set mechanic) | 17 | todo |
| search library | 16 | partial (`search_library`: hand or battlefield, tapped, reveal, count) |
| mana of any color / choices | 15 | todo (F10) |
| dies / leaves triggers (last-known information) | 13 | todo (F5) |
| **Strange new worlds** (set mechanic) | 13 | todo |
| copy | 12 | todo (707) |
| Sagas | 10 | todo |
| equipment / auras | 10 | done: enchant, equip, attach, "equipped/enchanted creature" statics, 704.5m/n (Bat'leth, Captain's Tutelage, Tricorder convert; the rest need stun counters, copy, granted triggers or type changes) |
| flying, menace, trample, vigilance, reach, lifelink, first strike, double strike, deathtouch, defender, ward | 1–9 each | todo (F11) |
| landfall | 9 | todo (F5) |
| **Face a dilemma** (set mechanic) | 8 | todo |
| cycling, landcycling, typecycling | 5 each | done (`cycling`, CR 702.29) |
| kicker, affinity, threshold, sunburst, explore, discover, fight, mill, investigate | 1–6 each | todo |
| **Assimilate** (set mechanic, CR 701.72 in the 2026-11-06 CR) | 2 | todo |
| one-off named abilities (flavor-named activated/triggered abilities) | ~40 | covered by the general ability system |

About 8 cards are supportable with today's engine.

## Phases

The structural core comes first (done: F1 frames, F2 `chars`, F3 ability refs,
F6 replacement seam). Each phase below ends with `bundle exec rake` and
`rake fuzz` green and the converter re-run (see *Pipeline*).

1. **Triggers and last-known information (F5).** Trigger events from the event
   stream, APNAP ordering through frames, targets chosen when put on the stack,
   intervening "if", delayed triggers. Unlocks ETB, dies, attacks, landfall,
   beginning-of-step and cast triggers (about 230 cards touch these).
2. **Expressive card data (F7, F8, F9).**
   - Parameterized filters: "creature you control", "nonland permanent",
     "with mana value N or less", legendary.
   - Amounts: X, "equal to", "for each", counts.
   - Conditions: "if", "unless", "as long as".
   - Modal spells, additional and alternative costs (kicker), casting from the graveyard.
3. **Core actions.** Exile, sacrifice, bounce, discard, tap/untap, search,
   scry/surveil/look-at-top, mill, fight, investigate.
4. **Tokens (F12)**, including predefined Treasure, Food and Clue, then copy effects.
5. **Evergreen keywords (F11)** and combat hooks: flying, reach, menace, trample,
   vigilance, lifelink, deathtouch, first and double strike (an extra damage
   step), defender, ward, indestructible, hexproof.
6. **Static abilities and the layer system (F4)**: anthems, grants, cost
   reduction, the legend rule, equipment and auras (attach).
7. **Mana (F10)**: any-color mana and choices; landcycling, typecycling, cycling.
8. **Set mechanics**: Station, Strange new worlds, Face a dilemma, Assimilate,
   Sagas. Re-pin the rules to the 2026-11-06 CR here: Assimilate is defined only
   there.
9. **Verification**: every card gets at least one scripted interaction scenario
   (integration spec) plus fuzz coverage through generated `trk` decks. The cast
   histogram must show every card cast or activated. Then the README "Verified
   sets" section.

## Pipeline

`script/convert_set` (to be written, run from the repo with network access):
1. Fetch the set from a card source (today the Scryfall API, `/cards/search?q=e:trk&unique=cards`; the converter keeps the source behind an adapter).
2. Map each card to Enjine data. Mechanical fields are mapped automatically, and
   abilities from a hand-maintained translation file:
   `data/translations/trk.json`, keyed by card name (names are unique across Magic).
3. Validate with `CardDefinition.from_h`, and write `lib/enjine/sets/trk.json`
   with `cards` (valid) and `unsupported` (name plus the missing capabilities).
4. The run prints the remaining count; the target is 0 unsupported.
