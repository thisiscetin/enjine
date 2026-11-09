# Program: every Standard mechanic implemented

**Goal.** The engine supports every mechanic used by cards of the Standard-legal
sets that stay legal past the next rotation, newest set first. **Cards are written
by hand** in the [card DSL](../guides/card-data-format.md). The engine never reads
card text, and the library ships no card data and no sets: cards reach it as data,
in decks or a `DeckBuilder` pool.

For each set:
1. List the mechanics its cards need (keywords, keyword actions, set mechanics,
   ability and effect shapes) and compare that list with `SUPPORTED.md`.
2. Implement each missing mechanic as a primitive, cite its Comprehensive Rules
   numbers, and test it at every level with **invented** cards (unit, integration,
   and fuzz through `spec/fixtures/cards/`).
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
first release is dated.

| # | Set | Released | Leaves Standard | Status |
| ---: | --- | --- | --- | --- |
| 1 | Star Trek | 2026-11-13 | 2029 (est.) | supported |
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | 18 gaps |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | 16 gaps |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | 18 gaps |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | 11 gaps |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | 10 gaps |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | 14 gaps |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | 14 gaps |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | 12 gaps |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | 17 gaps |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | 14 gaps |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | 16 gaps |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | 14 gaps |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | 17 gaps |

**Out of scope:** sets that are no longer Standard-legal, or that rotate out at the
next announced rotation, are out of scope. On 2027-02-05 Wilds of Eldraine, The
Lost Caverns of Ixalan, Murders at Karlov Manor, Outlaws of Thunder Junction,
Bloomburrow and Duskmourn leave Standard, so they're skipped (the maintainer
decided this on 2026-11-08). When a new set releases, add it at the top. When a
rotation is announced, drop the rotating sets from this table.

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
  controlling another player's turn (CR 724), granted loyalty abilities,
  "attacks alone" triggers and pile splitting. (Deck-construction exceptions,
  CR 100.2a, and odd/even choices were also seen and are now supported.)
- Ability words (landfall, threshold, raid, …) are not gaps in themselves; only
  what they need is listed. Sagas, Spacecraft/station, Planets, Equipment, Auras,
  modal spells, hybrid `{R/G}` mana, planeswalkers and legendary permanents
  are supported.
- A set's **Status** in the table above is its number of distinct gaps, or
  "supported" when none is left. Gaps closed since the census are listed under
  "Closed since the census" at the end of this section.

**Top gaps across all sets** (cards affected summed over the sets):

| Mechanic | CR | ~Cards | Sets |
| --- | --- | ---: | ---: |
| Behold | 701.4 | 21 | 4 |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 21 | 4 |
| Discard a card as a cost | 118.3, 701.9a | 20 | 9 |
| Ability removal (loses all abilities) | 613.1f | 19 | 10 |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 17 | 11 |
| Damage modification / redirection replacement | 614.1a, 616 | 13 | 9 |
| Pay life as a cost | 119.4, 118.3 | 13 | 9 |
| Monocolored hybrid mana {2/W} | 107.4e | 13 | 3 |
| Additional combat / ending the turn | 500.8, 725 | 11 | 8 |

### Star Trek (trk) — supported

311 cards.

No listed gap remains.

### Reality Fracture (fra) — 18 gaps

285 cards (at the census, about 181 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Noncombat damage trigger condition | 120.2b, 603.2 | 6 | Command the Stage |
| Discard a card as a cost | 118.3, 701.9a | 4 | Hallway Heckler |
| Emblems | 114 | 3 | Ajani Resolute |
| Ability removal (loses all abilities) | 613.1f | 2 | Flourishing Grapple |
| Behold | 701.4 | 2 | Countersculpt |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 2 | Danitha, Spear of Agony |
| Combat damage assignment changes | 510.1 | 2 | Ghalta the Immovable |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Proft, Sinister Mastermind |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Tomik, Izzet Sparkmage |
| Excess damage | 120.4a | 1 | Violent Echoes |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Gallia, Tragic Host |
| Monocolored hybrid mana {2/W} | 107.4e | 1 | Karn, Gilded Guardian |
| Proliferate | 701.34 | 1 | Tam, the Possibility |
| Random choices (discard at random) | 701.9b | 1 | Curse-Marred Demon |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | Garruk, Veiled Butcher |
| Trigger: blocks | 509.3a, 603.2 | 1 | Tetsuko Umezawa, Pursuer |
| Trigger: is dealt damage | 120.3, 603.2 | 1 | Hexhaven Invigorator |
| Static type change with a base P/T ("is a 5/5 creature in addition to its other types") | 613.1d, 205.1b | 1 | Puppet Crafting |

### The Hobbit (hob) — 16 gaps

193 cards (at the census, about 121 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Discard a card as a cost | 118.3, 701.9a | 2 | Key to the Side-Door |
| Mana spent: which sources paid it ("mana from a Treasure") | 601.2h, 207.2c | 1 | Smaug, Wicked Worm |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Bilbo's Gambit |
| Pay life as a cost | 119.4, 118.3 | 2 | Desolation Prowler |
| Ability removal (loses all abilities) | 613.1f | 1 | Enchanted River's Grasp |
| Additional combat / ending the turn | 500.8, 725 | 1 | Desert Were-Worm |
| Behold | 701.4 | 1 | Elven Passage |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Old Fat Spider Can't See Me |
| Divide damage among targets | 601.2d | 1 | Gandalf, Spark Starter |
| Excess damage | 120.4a | 1 | Bolg of the North |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Bilbo, Luckwearer |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 1 | Bilbo, Thief in the Night |
| Gift | 702.174 | 1 | Bilbo's Gambit |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Bilbo, Thief in the Night |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | Head of the Hunt |
| Token doubling replacement | 614.1a, 111.1 | 1 | Bard, King of Dale |

### Marvel Super Heroes (msh) — 18 gaps

281 cards (at the census, about 192 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 6 | Colleen Wing, Street Samurai |
| Ability removal (loses all abilities) | 613.1f | 3 | Frozen in Ice |
| Pay life as a cost | 119.4, 118.3 | 3 | M.O.D.O.K. |
| Trigger: is dealt damage | 120.3, 603.2 | 3 | Bruce Banner |
| Discard a card as a cost | 118.3, 701.9a | 2 | Bullseye, Death Dealer |
| Improvise | 702.126 | 2 | Arc Reactor |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Jennifer Walters |
| Additional combat / ending the turn | 500.8, 725 | 1 | Bruce Banner |
| Combat damage assignment changes | 510.1 | 1 | The Kingpin of Crime |
| Continuous control duration "for as long as" | 611.2b, 613.1b | 1 | The Super Hero Civil War |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Hawkeye, Young Avenger |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | King T'Challa |
| Divide damage among targets | 601.2d | 1 | Death to Our Enemies |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Baron Helmut Zemo |
| Granting activated abilities | 613.1f, 602.1 | 1 | Iron Fist, Living Weapon |
| Noncombat damage trigger condition | 120.2b, 603.2 | 1 | Hawkeye, Young Avenger |
| Player counters (poison, rad, experience) | 122.1f, 729 | 1 | The Serpent Society |
| Trigger: blocks | 509.3a, 603.2 | 1 | Super-Soldier Serum |

### Secrets of Strixhaven (sos) — 11 gaps

271 cards (at the census, about 158 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 12 | Conciliator's Duelist |
| Paradigm | 702.192 | 5 | Decorum Dissertation |
| Discard a card as a cost | 118.3, 701.9a | 3 | Charging Strifeknight |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 3 | Lluwen, Exchange Student |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Nita, Forum Conciliator |
| Monocolored hybrid mana {2/W} | 107.4e | 2 | Magmablood Archaic |
| Emblems | 114 | 1 | Professor Dellian Fel |
| Excess damage | 120.4a | 1 | Archaic's Agony |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Impractical Joke |
| Pay life as a cost | 119.4, 118.3 | 1 | Great Hall of the Biblioplex |
| Skip steps or turns | 614.10 | 1 | Ral Zarek, Guest Lecturer |

### Teenage Mutant Ninja Turtles (tmt) — 10 gaps

195 cards (at the census, about 133 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Random choices (discard at random) | 701.9b | 2 | Casey Jones, Vigilante |
| Trigger: is dealt damage | 120.3, 603.2 | 2 | Raphael, Ninja Destroyer |
| Ability removal (loses all abilities) | 613.1f | 1 | Retro-Mutation |
| Additional combat / ending the turn | 500.8, 725 | 1 | Raph & Leo, Sibling Rivals |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Raphael, Ninja Destroyer |
| Discard a card as a cost | 118.3, 701.9a | 1 | Mondo Gecko |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Kitsune, Dragon's Daughter |
| Hexproof from / protection from | 702.11d, 702.16 | 1 | Mondo Gecko |
| Mana spent compared with another amount ("less than its mana value") | 601.2h, 207.2c | 1 | Tokka & Rahzar, Terrible Twos |
| Trigger: blocks | 509.3a, 603.2 | 1 | Bebop & Rocksteady |

### Lorwyn Eclipsed (ecl) — 14 gaps

273 cards (at the census, about 166 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Behold | 701.4 | 12 | Celestial Reunion |
| Ability removal (loses all abilities) | 613.1f | 4 | Abigale, Eloquent First-Year |
| Hexproof from / protection from | 702.11d, 702.16 | 3 | Figure of Fable |
| Discard a card as a cost | 118.3, 701.9a | 2 | Iron-Shield Elf |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Hexing Squelcher |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Vinebred Brawler |
| Combat damage assignment changes | 510.1 | 1 | Bark of Doran |
| Copy abilities on the stack | 707.10 | 1 | Kirol, Attentive First-Year |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Morningtide's Light |
| Emblems | 114 | 1 | Oko, Lorwyn Liege |
| Pay life as a cost | 119.4, 118.3 | 1 | Champion of the Weird |
| Proliferate | 701.34 | 1 | High Perfect Morcant |
| Trigger: blocks | 509.3a, 603.2 | 1 | Doran, Besieged by Time |

### Avatar: The Last Airbender (tla) — 11 gaps

286 cards (at the census, about 168 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Ability removal (loses all abilities) | 613.1f | 2 | Day of Black Sun |
| Excess damage | 120.4a | 2 | Razor Rings |
| Additional combat / ending the turn | 500.8, 725 | 1 | Bumi, Unleashed |
| Copy abilities on the stack | 707.10 | 1 | Firebender Ascension |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Fated Firepower |
| Discard a card as a cost | 118.3, 701.9a | 1 | Professor Zei, Anthropologist |
| Foretell | 702.143 | 1 | Sozin's Comet |
| Granting activated abilities | 613.1f, 602.1 | 1 | Trusty Boomerang |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Avatar's Wrath |
| Pay life as a cost | 119.4, 118.3 | 1 | Koh, the Face Stealer |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 1 | Avatar's Wrath |

### Spider-Man (spm) — 12 gaps

193 cards (at the census, about 129 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Spells cast from anywhere other than hand (trigger / cost filter) | 601.2, 603.2 | 3 | Shadow of the Goblin |
| Ability removal (loses all abilities) | 613.1f | 2 | Lizard, Connors's Curse |
| Discard a card as a cost | 118.3, 701.9a | 2 | Inner Demons Gangsters |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Spider-Man 2099 |
| Choosing a basic land type ("this land is the chosen type") | 614.12, 607.2 | 1 | Multiversal Passage |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | With Great Power . . . |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | Anti-Venom, Horrifying Healer |
| Excess damage | 120.4a | 1 | Rhino's Rampage |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Mister Negative |
| Granting activated abilities | 613.1f, 602.1 | 1 | Friendly Neighborhood |
| Trigger: blocks | 509.3a, 603.2 | 1 | Spider-Mobile |
| Trigger: is dealt damage | 120.3, 603.2 | 1 | Strength of Will |

### Edge of Eternities (eoe) — 17 gaps

266 cards (at the census, about 188 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 3 | Desculpting Blast |
| Granting activated abilities | 613.1f, 602.1 | 2 | Ragost, Deft Gastronaut |
| Trigger: is dealt damage | 120.3, 603.2 | 2 | Pain for All |
| Combat damage assignment changes | 510.1 | 1 | Tapestry Warden |
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

### Final Fantasy (fin) — 14 gaps

312 cards (at the census, about 203 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Damage modification / redirection replacement | 614.1a, 616 | 4 | Ancient Adamantoise |
| Additional combat / ending the turn | 500.8, 725 | 3 | Balthier and Fran |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 3 | Magitek Scythe |
| Meld | 701.42, 713 | 3 | Fang, Fearless l'Cie |
| Damage prevention (beyond prevent all damage to you) | 615 | 2 | Crystal Fragments |
| Emblems | 114 | 2 | Sephiroth, Fabled SOLDIER |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Quistis Trepe |
| Pay life as a cost | 119.4, 118.3 | 2 | Ring of the Lucii |
| Mana of the chosen color | 614.12, 607.2 | 1 | Crossroads Village |
| Coin flip / die roll | 705, 706 | 1 | The Gold Saucer |
| Hexproof from / protection from | 702.11d, 702.16 | 1 | Absolute Virtue |
| Hideaway | 702.75 | 1 | Clive's Hideaway |
| Random choices (discard at random) | 701.9b | 1 | Sin, Spira's Punishment |
| Static dies-to-exile replacement (not a one-turn effect) | 614.1a | 1 | The Darkness Crystal |

### Tarkir: Dragonstorm (tdm) — 16 gaps

276 cards (at the census, about 189 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Monocolored hybrid mana {2/W} | 107.4e | 10 | Defibrillating Current |
| Behold | 701.4 | 6 | Caustic Exhale |
| Divide damage among targets | 601.2d | 2 | Twin Bolt |
| Hexproof from / protection from | 702.11d, 702.16 | 2 | Dragonfire Blade |
| Suspend / time counters | 702.62 | 2 | Stalwart Successor |
| Ability removal (loses all abilities) | 613.1f | 1 | Fresh Start |
| Additional combat / ending the turn | 500.8, 725 | 1 | All-Out Assault |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Neriv, Heart of the Storm |
| Damage prevention (beyond prevent all damage to you) | 615 | 1 | New Way Forward |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 1 | Great Arashin City |
| Granting activated abilities | 613.1f, 602.1 | 1 | Ringing Strike Mastery |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Voice of Victory |
| Pay life as a cost | 119.4, 118.3 | 1 | Krumar Initiate |
| Random choices (discard at random) | 701.9b | 1 | Tersa Lightshatter |
| Token doubling replacement | 614.1a, 111.1 | 1 | Elspeth, Storm Slayer |

### Aetherdrift (dft) — 12 gaps

276 cards (at the census, about 139 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Type change depending on each object ("an artifact creature if it's a Vehicle") | 613.1d, 205.1b | 1 | Alacrian Armory |
| A chosen creature type added to other types ("is the chosen type in addition") | 614.12, 607.2 | 1 | Lifecraft Engine |
| Discard a card as a cost | 118.3, 701.9a | 3 | Avishkar Raceway |
| Exile cards from graveyard as a cost (not the card itself) | 118.3, 406.1 | 3 | Earthrumbler |
| Ability removal (loses all abilities) | 613.1f | 1 | Flood the Engine |
| Additional combat / ending the turn | 500.8, 725 | 1 | Full Throttle |
| Continuous control duration "for as long as" | 611.2b, 613.1b | 1 | Possession Engine |
| Damage modification / redirection replacement | 614.1a, 616 | 1 | Far Fortune, End Boss |
| Emblems | 114 | 1 | Chandra, Spark Hunter |
| Exchange (control, life totals, P/T) | 701.12, 613.4d | 1 | Trade the Helm |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 1 | Pyrewood Gearhulk |
| Pay life as a cost | 119.4, 118.3 | 1 | The Last Ride |

### Foundations (fdn) — 17 gaps

517 cards (at the census, about 454 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| A chosen creature type added to other types ("is the chosen type in addition") | 614.12, 607.2 | 1 | Adaptive Automaton |
| Hexproof from / protection from | 702.11d, 702.16 | 4 | Elenda, Saint of Dusk |
| Damage prevention (beyond prevent all damage to you) | 615 | 3 | Crystal Barricade |
| Ability removal (loses all abilities) | 613.1f | 2 | Eaten by Piranhas |
| Additional combat / ending the turn | 500.8, 725 | 2 | Aurelia, the Warleader |
| Damage modification / redirection replacement | 614.1a, 616 | 2 | Gratuitous Violence |
| Emblems | 114 | 2 | Kaito, Cunning Infiltrator |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | 2 | Giant Cindermaw |
| Noncombat damage trigger condition | 120.2b, 603.2 | 2 | Crystal Barricade |
| Activate only once (per game) | 602.5b | 1 | Mild-Mannered Librarian |
| Blocking rules (block additional creatures, must be blocked, lure) | 509.1a, 509.1c | 1 | Joraga Invocation |
| Cast trigger filtered on the spell's targets | 603.2, 115.1 | 1 | Gnarlback Rhino |
| Divide damage among targets | 601.2d | 1 | Chandra, Flameshaper |
| Excess damage | 120.4a | 1 | Goblin Negotiation |
| Granting activated abilities | 613.1f, 602.1 | 1 | Fishing Pole |
| Player counters (poison, rad, experience) | 122.1f, 729 | 1 | Fynn, the Fangbearer |
| Token doubling replacement | 614.1a, 111.1 | 1 | Doubling Season |

### Closed since the census

These gaps were removed from the per-set tables above (their primitives are in
`SUPPORTED.md` and `docs/guides/card-data-format.md`). A row that was only partly
closed stays under a narrower name with the cards known to need it.

| Gap | Rules | Now written as (card-data-format section) |
| --- | --- | --- |
| Variable number of targets (X targets, any number of targets) | 601.2c, 115.3 | target spec `"count": "x" \| n \| amount \| "any"` (+ `"optional"` for "up to"); decision `choose_target_count` (4.2) |
| Filters on keyword abilities ("creature with flying") | 702.1, 115.1 | filter `"keywords"` / `"not_keywords"` (4.4) |
| Choosing a color, creature type, card type or named option (as it enters or on resolution) | 614.12, 607.2d, 607.2f | `choose_color` / `choose_creature_type` / `choose_card_type` / `choose_option` (abilities and effects); filters `"…": "chosen"`; condition `{"chosen": word}` (4.15) |
| "A deck can have any number of cards named ~" | 100.2a | card field `"deck_limit": "any"` (or a number) (2) |
| Vehicles / crew | 702.122, 301.7 | ability `crew`; triggers `becomes_crewed`, `crews_vehicle`; printed P/T on a Vehicle (4.16) |
| Type-changing effects (becomes a creature, gains a card type) | 613.1d, 205.1b | effect `become` (types, subtypes, colors, keywords, abilities, base P/T); static `types` (4.16) |
| Exhaust (activate only once) | 702.177 | `"exhaust": true` on an activated ability; trigger filter `activates_ability` `exhaust` (4.16) |
| Start your engines! / max speed | 702.179, 702.178 | keyword `start_your_engines`; ability `max_speed`; amount `speed`; condition `max_speed` (4.16) |
| Double-faced cards (transform / modal DFC) | 712, 701.27 | `layout` + `faces`; effect `transform`; trigger `transforms`; `return_to_battlefield` `transformed` (4.17) |
| Adventurer cards, Omen cards | 716, 721 | layouts `adventure`, `omen` (4.17) |
| Preparation cards / prepared | 723 | layout `prepare`; effects `prepare` / `unprepare`; ability `enters_prepared` (4.17) |
| Flashback, harmonize, mayhem, warp, evoke, web-slinging, sneak | 702.34, 702.180, 702.187, 702.185, 702.74, 702.188, 702.190 | abilities of the same names with a `cost`; conditions `cast_with`, `cast_from`, `cast_with_this_turn` (4.10) |
| Convoke | 702.51 | keyword `convoke` (4.10) |
| Turn-history conditions (you attacked, a permanent left the battlefield, cards drawn / sacrificed / exiled this turn) | 508.1, 400.7 | condition `you_attacked_this_turn`; amounts `left_this_turn`, `sacrificed_this_turn`, `attackers_this_turn`, `exiled_this_turn`, `cards_drawn_this_turn`, `cards_discarded_this_turn` (4.11) |
| Trigger: leaves the battlefield; more trigger events (discard, cycle, sacrifice, scry/surveil, put into a zone, becomes untapped) | 603.2, 603.6c, 603.10a | triggers `leaves_battlefield`, `sacrifices`, `discards`, `cycles`, `scries`, `surveils`, `becomes_untapped`, `put_into`, with `batched` "one or more" (4.5b) |
| Mana spent to cast a spell (converge, "if N or more mana was spent") | 601.2h, 207.2c | amount `mana_spent` (4.18) |
| Prowess, job select | 702.108, 702.182 | keywords `prowess`, `job_select` (4.19) |
| Mobilize, firebending | 702.181, 702.189 | abilities `mobilize`, `firebending` (4.19) |
| Blight, connive, recruit, amass, empower Jace, endure | 701.68, 701.50, 701.70, 701.47, 701.71, 701.63 | effects of the same names; cost `blight` (4.19) |
| Kindred card type | 308 | `"types": ["kindred", …]` (4.19) |
| Earthbend, waterbend, airbend | 701.66, 701.67, 701.65 | effects `earthbend`, `airbend`; cost `waterbend` (also in `pay`, `counter_unless_pays`, `ward`); triggers `earthbends`, `waterbends`, `airbends`, `firebends` (4.19) |
| Saddle (Mounts), exert | 702.171, 701.43 | ability `saddle`; effect `become_saddled`; filter `saddled`; triggers `becomes_saddled`, `saddles_mount`; cost `exert` (4.19) |
| Decayed, wither | 702.147, 702.80 | keywords `decayed` (and its counter), `wither` (4.19) |
| Power-up, boast | 702.193, 702.142 | `"power_up": true` / `"boast": true` on an activated ability (4.20) |
| Teamwork | 702.194 | ability `teamwork`; condition `{"cast_with": "teamwork"}` (4.20) |
| Tiered | 702.183 | a `cost` on each mode of a modal spell (4.20) |
| Class cards | 717 | ability `class_level`; trigger `becomes_level` (4.20) |
| Increment, extort, riot, storm, cascade | 702.191, 702.101, 702.136, 702.40, 702.85 | keywords of the same names (4.20) |
| Storied (enduring story designation) | 702.195 | keyword `storied`; condition `{"designation": "enduring_story"}` (4.20) |
| Colors among permanents, domain | 105.2, 305.6 | amounts `distinct_colors`, `distinct_land_types` (4.20) |

Still open in these areas (not yet counted as gaps above, since the census didn't
separate them):
- Pilots that crew or saddle "as though [their] power were 2 greater" or with toughness (about 13
  Aetherdrift cards), and "can't crew Vehicles" (CR 702.122d).
- Casting a card "by waterbending {X}" rather than paying its mana cost (Hama, the Bloodbender), an optional
  additional cost that isn't kicker ("you may waterbend {4}" is written as `kicker`), and a spell copy gaining
  wither (Spinerock Tyrant).
- Granting flashback, harmonize, mayhem or web-slinging to other cards; "cost {N} less"
  for spells cast from anywhere other than your hand (the remaining "Spells cast from
  anywhere other than hand" rows); "as though exhaust abilities haven't been activated".
- Endure with a computed N (the Spirit token's size is fixed), amass or empower by
  another player, optional or alternative blight costs, and triggers on blighting,
  firebending or conniving.
- Casting a card transformed (disturb, CR 712.8a), convert (CR 701.28), day/night
  (CR 702.145) and the mana value of a transformed back face (CR 712.6d); meld is a
  gap of its own.
- A type change that replaces the other types or lasts "until your next turn".
- "Whenever you cycle or discard a card" triggering only once for a cycled card
  (CR 702.29d); amounts from another leaving object's last known counters; "a card put
  into your graveyard from anywhere this turn" as a target filter.
- A card spec (library search) matching the chosen type, and a static that grants
  keywords to creatures filtered by keywords (layer-6 dependency, CR 613.8).
- Set mechanics: granting cascade or riot to other spells or permanents (Quandrix, the Proof;
  Spider-Punk), "becomes tapped to pay a teamwork cost" (Agent Maria Hill), "effects that refer
  to boasting" (CR 702.142b), a riot permanent with another "as this enters" choice, and the
  choice of hybrid half when a power-up cost is reduced (CR 118.7e: the half the cost needs is
  taken).

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
