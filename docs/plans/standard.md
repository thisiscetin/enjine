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
| 1 | Star Trek | 2026-11-13 | 2029 (est.) | 1 gap |
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | 28 gaps |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | 27 gaps |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | 32 gaps |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | 22 gaps |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | 18 gaps |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | 28 gaps |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | 26 gaps |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | 24 gaps |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | 26 gaps |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | 27 gaps |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | 28 gaps |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | 21 gaps |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | 25 gaps |

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

## Mechanics gaps

Census taken 2026-11-09 against `SUPPORTED.md` at this commit. It lists what can't
yet be written in the card DSL. Card lists came from the Scryfall API (main sets,
`unique=cards`, no bonus sheets) and were checked outside the repository; nothing
derived from card text is stored here.

- **Star Trek** was checked card by card: each of its 311 cards was written mentally
  in the DSL.
- **The other sets** were checked by keyword ability and keyword action (Scryfall's
  keyword lists, matched against CR 701/702), by card layout, and by a
  phrase classifier for recurring ability and effect shapes, calibrated by reading
  samples of each set's unflagged cards. Their counts are approximate (`~Cards` is
  how many cards show the shape), and rare one-off shapes may be missing. Seen
  once or twice in samples and not listed below: ward with a non-mana cost,
  controlling another player's turn (CR 724), deck-construction exceptions
  ("any number of cards named …", CR 100.2a), granted loyalty abilities,
  "attacks alone" triggers, pile splitting, and odd/even choices.
- Ability words (landfall, threshold, raid, …) are not gaps in themselves; only
  what they need is listed. Sagas, Spacecraft/station, Planets, Equipment, Auras,
  modal spells, hybrid `{R/G}` mana, planeswalkers and legendary permanents
  are supported.
- A set's **Status** in the table above is its number of distinct gaps.

**Top gaps across all sets** (cards affected summed over the sets):

| Mechanic | CR | ~Cards | Sets |
| --- | --- | ---: | ---: |
| Vehicles / crew | 702.122, 301.7 | 67 | 9 |
| Preparation cards / prepared | 723 | 62 | 2 |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 53 | 5 |
| Flashback | 702.34 | 42 | 7 |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 42 | 6 |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 42 | 7 |
| Start your engines! / max speed | 702.179, 702.178 | 40 | 1 |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 37 | 11 |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 36 | 13 |
| Empower Jace (planeswalker token) | 701.71 | 35 | 1 |
| Exhaust (activate only once) | 702.177 | 35 | 3 |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 34 | 8 |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 34 | 7 |
| Warp | 702.185 | 32 | 1 |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 31 | 13 |

### Star Trek (trk) — 1 gap

311 cards; about 310 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 1 | Dominion Infiltration |

### Reality Fracture (fra) — 28 gaps

285 cards; about 181 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Empower Jace (planeswalker token) | 701.71 | 35 | Academic Ascent |
| Preparation cards / prepared | 723 | 24 | Bloodline Recollector|
| Prowess | 702.108 | 9 | Cryotheory Adept |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 6 | Denzilore Fatehold |
| Noncombat damage trigger condition | 120.2b, 603.2 | 6 | Command the Stage |
| Flashback | 702.34 | 5 | Bestial Incursion |
| Discard a card as a cost | 118.3, 701.9a | 4 | Hallway Heckler|
| Emblems | 114 | 3 | Ajani Resolute |
| Ability removal (loses all abilities) | 613.1f | 2 | Flourishing Grapple |
| Behold | 701.4 | 2 | Countersculpt |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 2 | Danitha, Spear of Agony |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 2 | Kindred Judgment |
| Combat damage assignment changes | 510.1 | 2 | Ghalta the Immovable |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 2 | Konstrari Charm |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Proft, Sinister Mastermind |
| Convoke | 702.51 | 1 | Winter, Team Player |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Tomik, Izzet Sparkmage |
| Domain (basic land types among lands you control) | 305.6, 207.2c | 1 | Fblthp, Knows the Way |
| Excess damage | 120.4a | 1 | Violent Echoes |
| Exhaust (activate only once) | 702.177 | 1 | Liliana the Repentant |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Gallia, Tragic Host |
| Monocolored hybrid mana {2/W} | 107.4e | 1 | Karn, Gilded Guardian |
| Proliferate | 701.34 | 1 | Tam, the Possibility |
| Random choices (discard at random) | 701.9b | 1 | Curse-Marred Demon |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | Garruk, Veiled Butcher |
| Trigger: blocks | 509.3a, 603.2 | 1 | Tetsuko Umezawa, Pursuer |
| Trigger: is dealt damage | 120.3, 603.2 | 1 | Hexhaven Invigorator |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 1 | Puppet Crafting |

### The Hobbit (hob) — 27 gaps

193 cards; about 121 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Adventurer cards | 716 | 17 | An Unexpected Party|
| Amass (Army token) | 701.47 | 14 | Along the Crooked Way |
| Recruit | 701.70 | 10 | Bard's Company |
| Storied (enduring story designation) | 702.195 | 9 | Balin, Loremaster |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 3 | An Unexpected Party|
| Flashback | 702.34 | 3 | Moment of Glory |
| Discard a card as a cost | 118.3, 701.9a | 2 | Key to the Side-Door |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 2 | Smaug, Wicked Worm |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Bilbo's Gambit |
| Pay life as a cost | 119.4, 118.3 | 2 | Desolation Prowler |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 2 | Beorn's Hospitality |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 2 | The Eagles Are Coming! |
| Ability removal (loses all abilities) | 613.1f | 1 | Enchanted River's Grasp |
| Additional combat / ending the turn | 500.8, 725 | 1 | Desert Were-Worm |
| Behold | 701.4 | 1 | Elven Passage |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Old Fat Spider Can't See Me |
| Divide damage among targets | 601.2d | 1 | Gandalf, Spark Starter |
| Excess damage | 120.4a | 1 | Bolg of the North |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Bilbo, Luckwearer|
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 1 | Bilbo, Thief in the Night |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 1 | Warg Tactics |
| Gift | 702.174 | 1 | Bilbo's Gambit |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 1 | The Sackville-Bagginses |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Bilbo, Thief in the Night |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | Head of the Hunt |
| Token doubling replacement | 614.1a, 111.1 | 1 | Bard, King of Dale |
| Vehicles / crew | 702.122, 301.7 | 1 | Great Gilded Boat |

### Marvel Super Heroes (msh) — 32 gaps

281 cards; about 192 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Power-up | 702.193 | 24 | Abomination, Terrifying Titan |
| Teamwork | 702.194 | 12 | Atlantis Attacks |
| Connive | 701.50 | 11 | A.I.M. Scientists |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 6 | Colleen Wing, Street Samurai |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 6 | Bruce Banner|
| Prowess | 702.108 | 5 | Agent of Atlas |
| Ability removal (loses all abilities) | 613.1f | 3 | Frozen in Ice |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 3 | Iron Man Armor |
| Pay life as a cost | 119.4, 118.3 | 3 | M.O.D.O.K. |
| Trigger: is dealt damage | 120.3, 603.2 | 3 | Bruce Banner|
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 3 | I Am Iron Man |
| Vehicles / crew | 702.122, 301.7 | 3 | Dependable Quinjet |
| Discard a card as a cost | 118.3, 701.9a | 2 | Bullseye, Death Dealer |
| Improvise | 702.126 | 2 | Arc Reactor |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Jennifer Walters|
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 2 | Moonstone, Harsh Mistress |
| Additional combat / ending the turn | 500.8, 725 | 1 | Bruce Banner|
| Boast | 702.142 | 1 | Baron Helmut Zemo |
| Combat damage assignment changes | 510.1 | 1 | The Kingpin of Crime |
| Continuous control duration "for as long as" | 611.2b, 613.1b | 1 | The Super Hero Civil War |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Hawkeye, Young Avenger |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | King T'Challa|
| Divide damage among targets | 601.2d | 1 | Death to Our Enemies |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Baron Helmut Zemo |
| Extort | 702.101 | 1 | The Kingpin of Crime |
| Granting activated abilities | 613.1f, 602.1 | 1 | Iron Fist, Living Weapon |
| Noncombat damage trigger condition | 120.2b, 603.2 | 1 | Hawkeye, Young Avenger |
| Player counters (poison, rad, experience) | 122.1f, 729 | 1 | The Serpent Society |
| Sneak | 702.190 | 1 | Elektra, Daughter of the Hand |
| Trigger: blocks | 509.3a, 603.2 | 1 | Super-Soldier Serum |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 1 | Avengers Assemble! |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 1 | Super-Soldier Serum |

### Secrets of Strixhaven (sos) — 22 gaps

271 cards; about 158 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Preparation cards / prepared | 723 | 38 | Abigale, Poet Laureate|
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 22 | Aberrant Manawurm |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 12 | Conciliator's Duelist |
| Flashback | 702.34 | 9 | Antiquities on the Loose |
| Increment | 702.191 | 9 | Ambitious Augmenter |
| Paradigm | 702.192 | 5 | Decorum Dissertation |
| Discard a card as a cost | 118.3, 701.9a | 3 | Charging Strifeknight |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 3 | Lluwen, Exchange Student|
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 3 | Living History |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 3 | Divergent Equation |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Nita, Forum Conciliator |
| Monocolored hybrid mana {2/W} | 107.4e | 2 | Magmablood Archaic |
| Cascade | 702.85 | 1 | Quandrix, the Proof |
| Emblems | 114 | 1 | Professor Dellian Fel |
| Excess damage | 120.4a | 1 | Archaic's Agony |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 1 | Glorious Decay |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Impractical Joke |
| Pay life as a cost | 119.4, 118.3 | 1 | Great Hall of the Biblioplex |
| Skip steps or turns | 614.10 | 1 | Ral Zarek, Guest Lecturer |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Antiquities on the Loose |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 1 | Great Hall of the Biblioplex |
| Vehicles / crew | 702.122, 301.7 | 1 | Strixhaven Skycoach |

### Teenage Mutant Ninja Turtles (tmt) — 18 gaps

195 cards; about 133 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Sneak | 702.190 | 26 | Dark Leo & Shredder |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 9 | Featherbrained Filcher |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 9 | Foot Mystic |
| Class cards | 717 | 5 | Cool but Rude |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 4 | Does Machines |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 3 | Brilliance Unleashed |
| Random choices (discard at random) | 701.9b | 2 | Casey Jones, Vigilante |
| Trigger: is dealt damage | 120.3, 603.2 | 2 | Raphael, Ninja Destroyer |
| Vehicles / crew | 702.122, 301.7 | 2 | Turtle Blimp |
| Ability removal (loses all abilities) | 613.1f | 1 | Retro-Mutation |
| Additional combat / ending the turn | 500.8, 725 | 1 | Raph & Leo, Sibling Rivals |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Raphael, Ninja Destroyer |
| Discard a card as a cost | 118.3, 701.9a | 1 | Mondo Gecko |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Kitsune, Dragon's Daughter |
| Hexproof from / protection from | 702.11d, 702.16 | 1 | Mondo Gecko |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 1 | Tokka & Rahzar, Terrible Twos |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 1 | Cool but Rude |
| Trigger: blocks | 509.3a, 603.2 | 1 | Bebop & Rocksteady |

### Lorwyn Eclipsed (ecl) — 28 gaps

273 cards; about 166 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Blight | 701.68 | 24 | Blighted Blackthorn |
| Convoke | 702.51 | 15 | Appeal to Eirdu |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 13 | Bloodline Bidding |
| Kindred card type | 308 | 13 | Ashling's Command |
| Behold | 701.4 | 12 | Celestial Reunion |
| Colors among permanents (amount) | 105.2, 202.2 | 12 | Aurora Awakener |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 7 | Ashling, Rekindled|
| Evoke | 702.74 | 5 | Catharsis |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 5 | Catharsis |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 5 | Champion of the Clachan |
| Ability removal (loses all abilities) | 613.1f | 4 | Abigale, Eloquent First-Year |
| Hexproof from / protection from | 702.11d, 702.16 | 3 | Figure of Fable |
| Discard a card as a cost | 118.3, 701.9a | 2 | Iron-Shield Elf |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Hexing Squelcher |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 2 | Morningtide's Light |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Vinebred Brawler |
| Combat damage assignment changes | 510.1 | 1 | Bark of Doran |
| Copy abilities on the stack | 707.10 | 1 | Kirol, Attentive First-Year |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Morningtide's Light |
| Emblems | 114 | 1 | Oko, Lorwyn Liege|
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 1 | Unforgiving Aim |
| Flashback | 702.34 | 1 | Kindle the Inner Flame |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 1 | Moonshadow |
| Pay life as a cost | 119.4, 118.3 | 1 | Champion of the Weird |
| Proliferate | 701.34 | 1 | High Perfect Morcant |
| Trigger: blocks | 509.3a, 603.2 | 1 | Doran, Besieged by Time |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 1 | Firdoch Core |
| Wither | 702.80 | 1 | Spinerock Tyrant |

### Avatar: The Last Airbender (tla) — 26 gaps

286 cards; about 168 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Earthbend | 701.66 | 27 | Aang, at the Crossroads|
| Waterbend | 701.67 | 24 | Aang's Iceberg |
| Firebending | 702.189 | 21 | Avatar Aang|
| Airbend | 701.65 | 10 | Aang, Swift Savior|
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 8 | Aang, at the Crossroads|
| Exhaust (activate only once) | 702.177 | 8 | Bitter Work |
| Prowess | 702.108 | 7 | Firebending Student |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 6 | Pirate Peddlers |
| Vehicles / crew | 702.122, 301.7 | 6 | Fire Nation Warship |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 4 | Aang, at the Crossroads|
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 4 | Appa, Steadfast Guardian |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 3 | Momo, Friendly Flier |
| Flashback | 702.34 | 3 | Fire Nation Attacks |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 3 | Cruel Administrator |
| Ability removal (loses all abilities) | 613.1f | 2 | Day of Black Sun |
| Excess damage | 120.4a | 2 | Razor Rings |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 2 | Invasion Submersible |
| Additional combat / ending the turn | 500.8, 725 | 1 | Bumi, Unleashed |
| Copy abilities on the stack | 707.10 | 1 | Firebender Ascension |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Fated Firepower |
| Discard a card as a cost | 118.3, 701.9a | 1 | Professor Zei, Anthropologist |
| Foretell | 702.143 | 1 | Sozin's Comet |
| Granting activated abilities | 613.1f, 602.1 | 1 | Trusty Boomerang |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Avatar's Wrath |
| Pay life as a cost | 119.4, 118.3 | 1 | Koh, the Face Stealer |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Avatar's Wrath |

### Spider-Man (spm) — 24 gaps

193 cards; about 129 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Mayhem | 702.187 | 12 | Carnage, Crimson Chaos |
| Web-slinging | 702.188 | 9 | Arachne, Psionic Weaver |
| Connive | 701.50 | 7 | Doc Ock's Henchmen |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 7 | City Pigeon |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 5 | Eddie Brock|
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 3 | Shadow of the Goblin |
| Vehicles / crew | 702.122, 301.7 | 3 | Passenger Ferry |
| Ability removal (loses all abilities) | 613.1f | 2 | Lizard, Connors's Curse |
| Discard a card as a cost | 118.3, 701.9a | 2 | Inner Demons Gangsters |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 2 | Scout the City |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Spider-Man 2099 |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 2 | Living Brain, Mechanical Marvel |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 2 | Hide on the Ceiling |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 1 | Multiversal Passage |
| Convoke | 702.51 | 1 | Web of Life and Destiny |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | With Great Power . . . |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Anti-Venom, Horrifying Healer |
| Excess damage | 120.4a | 1 | Rhino's Rampage |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Mister Negative |
| Granting activated abilities | 613.1f, 602.1 | 1 | Friendly Neighborhood |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 1 | Hobgoblin, Mantled Marauder |
| Riot | 702.136 | 1 | Spider-Punk |
| Trigger: blocks | 509.3a, 603.2 | 1 | Spider-Mobile |
| Trigger: is dealt damage | 120.3, 603.2 | 1 | Strength of Will |

### Edge of Eternities (eoe) — 26 gaps

266 cards; about 188 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Warp | 702.185 | 32 | All-Fates Stalker |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 15 | Alpharael, Stonechosen |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 7 | Alpharael, Stonechosen |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 5 | Desculpting Blast |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 4 | Biotech Specialist |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 3 | Desculpting Blast |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 3 | Astelli Reclaimer |
| Granting activated abilities | 613.1f, 602.1 | 2 | Ragost, Deft Gastronaut |
| Trigger: is dealt damage | 120.3, 603.2 | 2 | Pain for All |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 2 | Synthesizer Labship |
| Combat damage assignment changes | 510.1 | 1 | Tapestry Warden |
| Convoke | 702.51 | 1 | Vote Out |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Cut Propulsion |
| Devour | 702.82 | 1 | Famished Worldsire |
| Emblems | 114 | 1 | Tezzeret, Cruel Captain |
| Excess damage | 120.4a | 1 | Orbital Plunge |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Rust Harvester |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Frenzied Baloth |
| Pay life as a cost | 119.4, 118.3 | 1 | Susur Secundi, Void Altar |
| Player counters (poison, rad, experience) | 122.1f, 729 | 1 | Virulent Silencer |
| Random choices (discard at random) | 701.9b | 1 | Alpharael, Stonechosen |
| Set life total | 119.5 | 1 | The Endstone |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Mm'menon, the Right Hand |
| Token doubling replacement | 614.1a, 111.1 | 1 | Exalted Sunborn |
| Trigger: blocks | 509.3a, 603.2 | 1 | Skystinger |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 1 | Singularity Rupture |

### Final Fantasy (fin) — 27 gaps

312 cards; about 203 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | 27 | Balamb Garden, SeeD Academy|
| Job select | 702.182 | 16 | Astrologian's Planisphere |
| Flashback | 702.34 | 14 | Auron's Inspiration |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | 9 | Blazing Bomb |
| Vehicles / crew | 702.122, 301.7 | 9 | Adventurer's Airship |
| Tiered | 702.183 | 6 | Fire Magic |
| Adventurer cards | 716 | 5 | Ishgard, the Holy See|
| Damage modification / redirection replacement | 614.1a, 616 | 4 | Ancient Adamantoise |
| Additional combat / ending the turn | 500.8, 725 | 3 | Balthier and Fran |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 3 | Magitek Scythe |
| Meld | 701.42, 713 | 3 | Fang, Fearless l'Cie |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 3 | Emet-Selch, Unsundered|
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 3 | Phantom Train |
| Damage prevention (beyond prevent all damage to you) | 615 | 2 | Crystal Fragments|
| Emblems | 114 | 2 | Sephiroth, Fabled SOLDIER|
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Quistis Trepe |
| Pay life as a cost | 119.4, 118.3 | 2 | Ring of the Lucii |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 1 | Crossroads Village |
| Coin flip / die roll | 705, 706 | 1 | The Gold Saucer |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 1 | Airship Crash |
| Hexproof from / protection from | 702.11d, 702.16 | 1 | Absolute Virtue |
| Hideaway | 702.75 | 1 | Clive's Hideaway |
| Prowess | 702.108 | 1 | Queen Brahne |
| Random choices (discard at random) | 701.9b | 1 | Sin, Spira's Punishment |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | The Darkness Crystal |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 1 | Zenos yae Galvus|
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 1 | Joshua, Phoenix's Dominant|

### Tarkir: Dragonstorm (tdm) — 28 gaps

276 cards; about 189 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Omen cards | 721 | 13 | Bloomvine Regent|
| Mobilize | 702.181 | 12 | Avenger of the Fallen |
| Endure | 701.63 | 10 | Anafenza, Unyielding Lineage |
| Harmonize | 702.180 | 10 | Channeled Dragonfire |
| Monocolored hybrid mana {2/W} | 107.4e | 10 | Defibrillating Current |
| Behold | 701.4 | 6 | Caustic Exhale |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 5 | Barrensteppe Siege |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 4 | Reverberating Summons |
| Divide damage among targets | 601.2d | 2 | Twin Bolt |
| Hexproof from / protection from | 702.11d, 702.16 | 2 | Dragonfire Blade |
| Prowess | 702.108 | 2 | Jeskai Brushmaster |
| Suspend / time counters | 702.62 | 2 | Stalwart Successor |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 2 | Rot-Curse Rakshasa |
| Ability removal (loses all abilities) | 613.1f | 1 | Fresh Start |
| Additional combat / ending the turn | 500.8, 725 | 1 | All-Out Assault |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Neriv, Heart of the Storm |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | New Way Forward |
| Decayed | 702.147 | 1 | Rot-Curse Rakshasa |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Great Arashin City |
| Granting activated abilities | 613.1f, 602.1 | 1 | Ringing Strike Mastery |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Voice of Victory |
| Pay life as a cost | 119.4, 118.3 | 1 | Krumar Initiate |
| Random choices (discard at random) | 701.9b | 1 | Tersa Lightshatter |
| Storm | 702.40 | 1 | Stormscale Scion |
| Token doubling replacement | 614.1a, 111.1 | 1 | Elspeth, Storm Slayer |
| Trigger: leaves the battlefield | 603.6c, 603.10a | 1 | Severance Priest |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 1 | Essence Anchor |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 1 | Reverberating Summons |

### Aetherdrift (dft) — 21 gaps

276 cards; about 139 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Vehicles / crew | 702.122, 301.7 | 41 | Air Response Unit |
| Start your engines! / max speed | 702.179, 702.178 | 40 | Aether Syphon |
| Exhaust (activate only once) | 702.177 | 26 | Afterburner Expert |
| Saddle (Mounts) | 702.171 | 13 | Alacrian Jaguar |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 12 | Alacrian Armory |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 7 | Captain Howler, Sea Scourge |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 3 | Lifecraft Engine |
| Discard a card as a cost | 118.3, 701.9a | 3 | Avishkar Raceway |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 3 | Earthrumbler |
| Ability removal (loses all abilities) | 613.1f | 1 | Flood the Engine |
| Additional combat / ending the turn | 500.8, 725 | 1 | Full Throttle |
| Continuous control duration "for as long as" | 611.2b, 613.1b | 1 | Possession Engine |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Far Fortune, End Boss |
| Emblems | 114 | 1 | Chandra, Spark Hunter |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Trade the Helm |
| Exert | 701.43 | 1 | Basri, Tomorrow's Champion |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 1 | Broken Wings |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Pyrewood Gearhulk |
| Pay life as a cost | 119.4, 118.3 | 1 | The Last Ride |
| Prowess | 702.108 | 1 | Riptide Gearhulk |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 1 | Riverchurn Monument |

### Foundations (fdn) — 25 gaps

517 cards; about 454 use no listed gap.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | 10 | Alesha, Who Laughs at Fate |
| Flashback | 702.34 | 7 | Bulk Up |
| Choosing a color, creature type or named option (as it enters or on resolution) | 614.12, 607.2 | 6 | Adaptive Automaton |
| More trigger events (discard, cycle, sacrifice, scry/surveil, put into exile or a graveyard from anywhere, becomes untapped) | 603.2 | 5 | Darksteel Colossus |
| Prowess | 702.108 | 5 | Drake Hatcher |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | 4 | Broken Wings |
| Hexproof from / protection from | 702.11d, 702.16 | 4 | Elenda, Saint of Dusk |
| Damage prevention (beyond prevent all damage to you) | 615 | 3 | Crystal Barricade |
| Ability removal (loses all abilities) | 613.1f | 2 | Eaten by Piranhas |
| Additional combat / ending the turn | 500.8, 725 | 2 | Aurelia, the Warleader |
| Damage modification / redirection replacement | 614.1a, 616 | 2 | Gratuitous Violence |
| Emblems | 114 | 2 | Kaito, Cunning Infiltrator |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Giant Cindermaw |
| Noncombat damage trigger condition | 120.2b, 603.2 | 2 | Crystal Barricade |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | 2 | Crawling Barrens |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.1 | 2 | Chandra, Flameshaper |
| Activate only once (per game) | 602.5b | 1 | Mild-Mannered Librarian |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Joraga Invocation |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 1 | Gnarlback Rhino |
| Divide damage among targets | 601.2d | 1 | Chandra, Flameshaper |
| Excess damage | 120.4a | 1 | Goblin Negotiation |
| Granting activated abilities | 613.1f, 602.1 | 1 | Fishing Pole |
| Player counters (poison, rad, experience) | 122.1f, 729 | 1 | Fynn, the Fangbearer |
| Token doubling replacement | 614.1a, 111.1 | 1 | Doubling Season |
| Vehicles / crew | 702.122, 301.7 | 1 | Cultivator's Caravan |

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
