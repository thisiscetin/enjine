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
| **Station** (set mechanic) | 17 | core done (see *Set mechanics* below) |
| search library | 16 | partial (`search_library`: hand or battlefield, tapped, reveal, count) |
| mana of any color / choices | 15 | todo (F10) |
| dies / leaves triggers (last-known information) | 13 | todo (F5) |
| **Strange new worlds** (set mechanic) | 13 | count done; cost reduction, X pumps and CDAs wait on F8/F10 |
| copy | 12 | todo (707) |
| Sagas | 10 | done (chapter effects still need their own capabilities) |
| equipment / auras | 10 | done: enchant, equip, attach, "equipped/enchanted creature" statics, 704.5m/n (Bat'leth, Captain's Tutelage, Tricorder convert; the rest need stun counters, copy, granted triggers or type changes) |
| flying, menace, trample, vigilance, reach, lifelink, first strike, double strike, deathtouch, defender, ward | 1–9 each | todo (F11) |
| landfall | 9 | todo (F5) |
| **Face a dilemma** (set mechanic) | 8 | trigger done; "dilemmas faced this turn" todo |
| cycling, landcycling, typecycling | 5 each | done (`cycling`, CR 702.29) |
| kicker, affinity, threshold, sunburst, explore, discover, fight, mill, investigate | 1–6 each | todo |
| **Assimilate** (set mechanic, CR 701.72 in the 2026-11-06 CR) | 2 | done; "exiled with" linkage (607) todo |
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
   Sagas. Core done; see *Set mechanics* below. `RULES_VERSION` stays pinned to
   2026-09-25 until the whole engine is re-pinned (see
   [standard.md](standard.md)); these mechanics cite the 2026-11-06 numbering.
9. **Verification**: every card gets at least one scripted interaction scenario
   (integration spec) plus fuzz coverage through generated `trk` decks. The cast
   histogram must show every card cast or activated. Then the README "Verified
   sets" section.

## Set mechanics

Rule numbers below are from the **2026-11-06** CR (`cr1106`), the first version
that defines assimilate. Where the pinned **2026-09-25** CR (`cr0925`) numbers the
same rule differently, both are given. Code comments and spec names use the
2026-11-06 numbers and say so.

| Mechanic | Rules used (2026-11-06) | 2026-09-25 | Card data | Status |
| --- | --- | --- | --- | --- |
| Station | 702.184a, 722.2a-c, 722.4, 302.6 | same numbers | keyword `station` (an intrinsic activated ability, ref `keyword:station`) + `station_symbol` abilities `{"at": N, "power", "toughness", "keywords", "abilities"}` | done |
| Tap another creature (the station cost) | 702.184a, 601.2h, 602.2b | same | cost `tap_another_creature`, decision `choose_cost` | done |
| Sagas | 715.2b-d, 715.3a, 715.3c, 715.4, 704.5s, 505.4, 122.6 | 714.x (same subrules), 704.5s, 505.4 | subtype `saga` + `chapter` abilities `{"chapter": N, targets, effects/modes}` | done |
| Face a dilemma | 700.17 | not in this version | trigger `faces_dilemma {"controller"}` | trigger done |
| Assimilate | 701.72a-b, 205.1b | not in this version | effect `assimilate`; filter `graveyard_card` | done |
| Strange new worlds | 207.2c (ability word: no rules meaning) | not listed | amount `{"distinct_names": selector}` | count done |
| Beam me up | 702.196a-b, 118.9, 601.2b, 601.2f-h | not in this version | ability `beam_me_up {"cost"}`, static `grants_beam_me_up`, flag `cant_be_beamed_up`; cast option `via: "beam:<ref>"`; the creature is a `choose_cost` decision, returned as the spell becomes cast | done |
| Casting from other zones | 601.3, 113.6e-f, 305.1, 401.5, 608.2g, 701.57 | same numbers | ability `play_from`, `look_at_top`; effects `exile_top`, `exile_until`, `play_permission`, `cast_free`, `discover`; permissions are `state.effects` of kind `permission` | done |

How they work:

- **Station symbols** apply in the layer pass from the permanent's own charge
  counters (`Engine::SetMechanics#own_layers`): layer 4 adds the creature type,
  layer 7b sets base P/T, then counters and pumps apply (7c). Abilities a symbol
  grants are part of the object's characteristics only while it applies; they
  have refs `printed:<i>:<j>` so triggers and stack objects resolve after the
  counters change. Static abilities see types after layer 4, so a stationed
  Spacecraft counts as an artifact creature. The station ability's counters use
  the tapped creature's power on resolution, or its power when tapped if it has
  left the battlefield (kept in the stack object's `paid`).
- **Sagas** enter with a lore counter (a replacement from the subtype, 715.3a);
  the precombat main step adds one (715.3c). Chapter abilities trigger on lore
  counters added or on entering with them (122.6), one trigger per chapter
  crossed. The 704.5s SBA waits while a chapter ability of the Saga is pending or
  on the stack, then the Saga is sacrificed (zone change reason `sacrifice`).
- **Dilemmas** are recorded as the spell or ability with chosen modes is cast,
  activated or put on the stack (event `dilemma_faced`), so cancelling a cast
  never counts.
- **Assimilate** changes control (event `control_changed`, newly controlled for
  302.6) or puts the card onto the battlefield, adds the +1/+1 counter, and adds a
  `state.effects` entry (`kind: "assimilate"`, duration `permanent`) that makes it
  an artifact creature whose creature types are replaced by Borg (205.1b).

Still to do:

- Read ahead (702.155) and Saga creatures (715.1a) are untested; no trk card needs them.
- 702.184c (effects that change what station counts).
- "Dilemmas faced this turn" (Captain Benjamin Sisko, The Caretaker): needs a
  per-player per-turn count in `PlayerState` (and the scenario helper).
- Assimilate's linked "exiled with" ability (701.72c, 607) for Borg Cube.
- Strange new worlds cost reductions, `pump` with computed amounts, and
  characteristic-defining P/T (Captain Pike, The Traveler) belong to F8/F10.
- `RulesMonitor` doesn't add static-ability pumps in its independent P/T check,
  so the converter's static-line pattern stays case-sensitive for now (enabling
  "Artifact creatures you control get +1/+0" makes the monitor report false
  findings).

Converted with these mechanics (converter phrasings or `data/translations/trk.json`):
Class-F Shuttlecraft, Suurok-Class Science Vessel, U.S.S. Cerritos, U.S.S. Excelsior
(station); Year of Hell (Saga); Elim Garak, Obsidian Order Operative, Melkotian
Adjudicator, Seven of Nine (dilemma); Death Is Irrelevant (assimilate, translation);
Excalbian Gamemaster (strange new worlds, translation).
Energize, Open Communications, Transporter Malfunction, Adversary by Algorithm, Federation
Resupply, Final Frontier, Scotty (beam me up, translations); Storied Veteran, Overflow
Submatrix, Zefram Cochrane (casting from the graveyard / library top); Reckless Impulse,
Silicate Surveyor, Encounter the Unknown, Ensign Pavel Chekov (impulse draw); U.S.S.
Discovery (discover); Andromedan Automatons, Oberth-Class Starship, Primary Unimatrix
Adjunct, Shields Up! (translations).
Waiting on other capabilities: Captain Benjamin Sisko and The Caretaker (dilemmas faced this
turn, token colors, ward), Captain Pike (characteristic-defining P/T), Kirk and Exploratory
Mission (total power, counters-on-self amounts), U.S.S. Enterprise-D (charge counters trigger),
Khan (choose and sacrifice), Brazen Bluff (a "may" decided by another player), Boarding Action
(token colors).

## Pipeline

`script/convert_set` (to be written, run from the repo with network access):
1. Fetch the set from a card source (today the Scryfall API, `/cards/search?q=e:trk&unique=cards`; the converter keeps the source behind an adapter).
2. Map each card to Enjine data. Mechanical fields are mapped automatically, and
   abilities from a hand-maintained translation file:
   `data/translations/trk.json`, keyed by card name (names are unique across Magic).
3. Validate with `CardDefinition.from_h`, and write `lib/enjine/sets/trk.json`
   with `cards` (valid) and `unsupported` (name plus the missing capabilities).
4. The run prints the remaining count; the target is 0 unsupported.
