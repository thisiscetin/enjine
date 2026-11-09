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
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | 4 gaps |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | 9 gaps |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | 4 gaps |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | 2 gaps |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | 2 gaps |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | 3 gaps |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | 5 gaps |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | 6 gaps |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | 6 gaps |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | 9 gaps |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | 5 gaps |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | 2 gaps |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | 4 gaps |

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
| Optional behold with a chosen creature type; behold or pay | 701.4, 601.2b | 12 | 1 |
| Behold or pay (choosing between costs) | 701.4, 601.2b | 8 | 2 |
| What happened last turn ("dealt noncombat damage last turn") | 120.2b, 603.4 | 6 | 1 |
| Divide damage among targets | 601.2d | 5 | 4 |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 5 | 3 |
| Paradigm | 702.192 | 5 | 1 |
| Damage prevention with a follow-up, a chosen source or a "for as long as" duration | 615.5, 615.8, 611.2b | 3 | 3 |
| Static that sets card types or the name ("is a black Skeleton creature", "named …") | 613.1a, 613.1d | 3 | 2 |
| Meld | 701.42, 713 | 3 | 1 |
| Dies-to-exile replacement with a follow-up ("When you do", "and you gain 2 life") | 614.1a, 603.12 | 2 | 2 |

### Star Trek (trk) — supported

311 cards.

No listed gap remains.

### Reality Fracture (fra) — 4 gaps

285 cards (at the census, about 181 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| What happened last turn ("dealt noncombat damage last turn") | 120.2b, 603.4 | 6 | Command the Stage |
| Behold or pay (choosing between costs) | 701.4, 601.2b | 2 | Countersculpt |
| Restriction on casting the spell itself ("can't cast this spell unless …") | 601.3 | 1 | Proft, Sinister Mastermind |
| Static type change with a base P/T ("is a 5/5 creature in addition to its other types") | 613.1d, 205.1b | 1 | Puppet Crafting |

### The Hobbit (hob) — 9 gaps

193 cards (at the census, about 121 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Attack trigger on total attacking power ("total power 12 or greater") | 508.1, 603.2 | 1 | Desert Were-Worm |
| Damage prevention with a follow-up, a chosen source or a "for as long as" duration | 615.5, 615.8, 611.2b | 1 | Old Fat Spider Can't See Me |
| Dies-to-exile replacement with a follow-up ("When you do", "and you gain 2 life") | 614.1a, 603.12 | 1 | Head of the Hunt |
| Discard cost matched against your permanents ("same name as a legendary permanent you control") | 118.3, 701.9a | 1 | Key to the Side-Door |
| Divide damage among targets | 601.2d | 1 | Gandalf, Spark Starter |
| Exchange of targets that share a card type | 701.12b, 115.1 | 1 | Bilbo, Luckwearer |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 1 | Bilbo, Thief in the Night |
| Gift | 702.174 | 1 | Bilbo's Gambit |
| Mana spent: which sources paid it ("mana from a Treasure") | 601.2h, 207.2c | 1 | Smaug, Wicked Worm |

### Marvel Super Heroes (msh) — 4 gaps

281 cards (at the census, about 192 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Choosing between costs ("sacrifice an artifact or discard a nonland card") | 118.3, 601.2b | 1 | Bullseye, Death Dealer |
| Divide damage among targets | 601.2d | 1 | Death to Our Enemies |
| Exile any number of graveyard cards as a cost, by mana symbols among them | 118.3, 406.1 | 1 | Baron Helmut Zemo |
| Ward with a non-mana cost ("Ward—Get five poison counters") | 702.21a | 1 | The Serpent Society |

### Secrets of Strixhaven (sos) — 2 gaps

271 cards (at the census, about 158 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Paradigm | 702.192 | 5 | Decorum Dissertation |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Nita, Forum Conciliator |

### Teenage Mutant Ninja Turtles (tmt) — 2 gaps

195 cards (at the census, about 133 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Hexproof from a chosen color | 702.11d | 1 | Mondo Gecko |
| Mana spent compared with another amount ("less than its mana value") | 601.2h, 207.2c | 1 | Tokka & Rahzar, Terrible Twos |

### Lorwyn Eclipsed (ecl) — 3 gaps

273 cards (at the census, about 166 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Optional behold with a chosen creature type; behold or pay | 701.4, 601.2b | 12 | Celestial Reunion |
| Protection from each of your opponents | 702.16 | 1 | Figure of Fable |
| Ward with a non-mana cost ("Ward—Pay 2 life") | 702.21a | 1 | Hexing Squelcher |

### Avatar: The Last Airbender (tla) — 5 gaps

286 cards (at the census, about 168 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Attack restriction for an added combat ("only land creatures can attack") | 508.1c | 1 | Bumi, Unleashed |
| Copying the ability that triggered ("you may copy that ability") | 707.10 | 1 | Firebender Ascension |
| Foretell | 702.143 | 1 | Sozin's Comet |
| Granted abilities that refer to the permanent granting them | 613.1f, 607.1 | 1 | Trusty Boomerang |
| Static that sets card types or the name ("is a black Skeleton creature", "named …") | 613.1a, 613.1d | 1 | Honest Work |

### Spider-Man (spm) — 6 gaps

193 cards (at the census, about 129 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Playing a land from anywhere other than hand (trigger, condition) | 305.1, 603.2 | 2 | Shadow of the Goblin |
| Amount "this way" read through a "may" | 608.2c | 1 | Mister Negative |
| Damage prevention with a follow-up, a chosen source or a "for as long as" duration | 615.5, 615.8, 611.2b | 1 | Anti-Venom, Horrifying Healer |
| Excess damage dealt in a fight | 120.4a, 701.14 | 1 | Rhino's Rampage |
| Restriction on casting the spell itself ("can't cast this spell unless …") | 601.3 | 1 | Spider-Man 2099 |
| Two "as this enters" choices on one permanent | 614.12 | 1 | Multiversal Passage |

### Edge of Eternities (eoe) — 6 gaps

266 cards (at the census, about 188 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Block restriction ("can block only creatures with flying") | 509.1b | 1 | Desculpting Blast |
| Devour | 702.82 | 1 | Famished Worldsire |
| Mana spendable only on spells cast from anywhere other than hand | 106.6, 601.2 | 1 | Mm'menon, the Right Hand |
| Station using toughness | 702.184a | 1 | Tapestry Warden |
| Trigger: plays a land | 305.1, 603.2 | 1 | The Endstone |
| Ward with a non-mana cost ("Ward—Discard a card at random") | 702.21a | 1 | Alpharael, Stonechosen |

### Final Fantasy (fin) — 9 gaps

312 cards (at the census, about 203 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Meld | 701.42, 713 | 3 | Fang, Fearless l'Cie |
| Exile-instead replacement for spells cast via an effect | 614.1a, 608.2n | 2 | Quistis Trepe |
| Prevention for a class of permanents decided as damage is dealt ("creatures you control") | 615.1, 611.2c | 2 | Crystal Fragments |
| "Repeat this process" loops | 608.2c | 1 | Sin, Spira's Punishment |
| Damage isn't removed during cleanup | 514.2 | 1 | Ancient Adamantoise |
| Dies-to-exile replacement with a follow-up ("When you do", "and you gain 2 life") | 614.1a, 603.12 | 1 | The Darkness Crystal |
| Ending the turn | 725 | 1 | Ultima |
| Hideaway | 702.75 | 1 | Clive's Hideaway |
| Protection from each of your opponents | 702.16 | 1 | Absolute Virtue |

### Tarkir: Dragonstorm (tdm) — 5 gaps

276 cards (at the census, about 189 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Behold or pay (choosing between costs) | 701.4, 601.2b | 6 | Caustic Exhale |
| Divide damage among targets | 601.2d | 2 | Twin Bolt |
| Suspend / time counters | 702.62 | 2 | Stalwart Successor |
| Damage modification for sources that entered this turn | 614.1a, 616 | 1 | Neriv, Heart of the Storm |
| Damage prevention with a follow-up, a chosen source or a "for as long as" duration | 615.5, 615.8, 611.2b | 1 | New Way Forward |

### Aetherdrift (dft) — 2 gaps

276 cards (at the census, about 139 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Duration "for as long as you control this" | 611.2b | 1 | Possession Engine |
| Type change depending on each object ("an artifact creature if it's a Vehicle") | 613.1d, 205.1b | 1 | Alacrian Armory |

### Foundations (fdn) — 4 gaps

517 cards (at the census, about 454 used no listed gap).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Ending the turn; "attacks for the first time each turn" | 725, 603.2 | 2 | Time Stop |
| Static that sets card types or the name ("is a black Skeleton creature", "named …") | 613.1a, 613.1d | 2 | Eaten by Piranhas |
| Divide damage among targets | 601.2d | 1 | Chandra, Flameshaper |
| Granted abilities that refer to the permanent granting them | 613.1f, 607.1 | 1 | Fishing Pole |

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
| Discard a card / pay life / exile cards from your graveyard as a cost (also as a spell's additional cost) | 701.9, 119.4, 118.3 | costs `discard` (`count`, `card`, `random`), `pay_life` (N or `"X"`), `exile_from_graveyard` (4.2) |
| Behold | 701.4 | cost `behold` (`exile`: linked `exiled_with`, also after leaving); effect `behold` under `may` (4.2) |
| Monocolored hybrid mana {2/W} | 107.4e, 202.3f | mana cost symbol `{2/W}` (2) |
| Improvise; mana of the chosen color; activate only once | 702.126, 607.2d, 602.5b | keyword `improvise` (4.10); mana `color: "chosen"` (3); `limit: "once"` (4.2) |
| Ability removal (loses all abilities) | 613.1f | `"loses_abilities": true` on `become` and `static`; static `colors`, `base_power_toughness` (4.21) |
| More player/game restrictions (can't cast, can't gain life, spells can't be countered, ...) | 101.2, 604.1 | `player_rule` rules `cant_cast` (`spells`), `cant_cast_except_from_hand`, `spells_cant_be_countered`, `cant_gain_life`, `cant_activate`, `damage_cant_be_prevented`, `combat_damage_cant_be_prevented`; `if` (4.21) |
| Hexproof from / protection from | 702.11d, 702.16 | abilities `hexproof_from` / `protection_from` with a card spec (`colors`, `color_count`) or `"everything"` (4.21) |
| Granting activated abilities | 613.1f, 602.1 | `static` / `become` `abilities` with `activated` (4.21) |
| Emblems | 114 | effect `create_emblem`; the command zone (4.21) |
| Exchange (control, life totals), set life total | 701.12, 119.5 | effects `exchange_control`, `exchange_life_totals`, `set_life` (4.21) |
| Player counters (poison, experience) | 122.1, 122.1f, 704.5c | `add_counters` on players; amount `counters` of players (4.21; rad counters' trigger, CR 729, not yet) |
| Skip turns | 614.10 | effect `skip_turns` (4.21) |
| A chosen type added to other types; choosing a basic land type | 614.12, 607.2 | static `"subtypes": "chosen"`; ability `choose_basic_land_type` (4.21) |
| Control "for as long as" | 611.2b | `gain_control` durations `while_source_on_battlefield`, `while_source_tapped` (4.21) |
| Damage modification and redirection (double, plus N, "dealt to this creature instead") | 614.1a, 614.9, 616.1 | static `damage_replacement` (`by`, `to`, `combat`; `multiply`, `plus`, `redirect`) (4.22) |
| Damage prevention; damage can't be prevented | 615, 615.7, 615.12 | static and effect `prevent_damage` (`next`: a shield), `damage_unpreventable`; also `player_rule` `damage_cant_be_prevented` (4.21, 4.22) |
| Trigger: is dealt damage; trigger: blocks; noncombat damage | 120.2b, 509.3a, 603.2 | triggers `dealt_damage`, `blocks`; `deals_damage` `noncombat`; amount `noncombat_damage_this_turn` (4.22) |
| Excess damage | 120.4a, 120.10 | `{"this_way": n}` of a `deal_damage` effect (4.22) |
| Must be blocked; assigns combat damage by toughness | 509.1c, 510.1a | keyword flags `must_be_blocked`, `assigns_damage_by_toughness` (4.22) |
| Additional combat (and main) phases | 500.8 | effect `additional_phases`; condition `first_combat_phase` (4.22) |
| Static dies-to-exile replacement; token doubling | 614.1a, 614.5 | statics `exile_if_dies`, `double_tokens` (4.22) |
| Cast trigger filtered on the spell's targets ("a spell that targets ~ / a creature you control") | 603.2, 115.1 | trigger `cast` with `"targets": filter \| "self"` (4.23) |
| Spells cast from anywhere other than your hand: trigger and cost filter | 601.2a, 603.2 | `"from"` / `"not_from"` on trigger `cast` and on `cost_modifier` (4.23) |
| Copy activated or triggered abilities on the stack | 707.10 | `copy_spell` of a `stack_ability` target (`kind`, `controller`, `source`) (4.23) |
| Random choices (discard at random, a card at random from a graveyard) | 701.9b | `"random": true` on `discard` and `choose_cards` (4.23) |
| Coin flips | 705 | effect `flip_coins` (`count`: wins \| heads), amount `{ "this_way": n }` (4.23) |
| Proliferate | 701.34a | effect `proliferate` (`amount`) (4.23) |

Still open in these areas (not yet counted as gaps above, since the census didn't
separate them):
- Choosing between costs ("behold a Goblin or pay {2}", "pay 5 life or pay {2}"), optional additional
  costs other than kicker ("you may behold two creatures of that type"), "as this enters, you may behold
  a Jace; if you don't, it enters tapped", "exile X cards from your graveyard", "discard your hand".
- Which sources' mana was spent ("if mana from a Treasure was spent") and "mana spent less than its
  mana value"; "Activate only if …" on mana abilities.
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
- Cast triggers: the targeted objects as "those creatures" (Storm, Windrider), and "you may choose new targets for
  that spell" (Speedball). Proliferating "X times, where X is the number of planeswalker types" (Tam) has no
  amount. Dice rolls (CR 706) aren't needed by any Standard card yet; coin-flip replacements (Edgar, CR 705.3)
  remain.
- A card spec (library search) matching the chosen type, and a static that grants
  keywords to creatures filtered by keywords (layer-6 dependency, CR 613.8).
- Set mechanics: granting cascade or riot to other spells or permanents (Quandrix, the Proof;
  Spider-Punk), "becomes tapped to pay a teamwork cost" (Agent Maria Hill), "effects that refer
  to boasting" (CR 702.142b), a riot permanent with another "as this enters" choice, and the
  choice of hybrid half when a power-up cost is reduced (CR 118.7e: the half the cost needs is
  taken).
- Rules and statics: rad counters' inherent trigger (CR 729); "can't activate" covering mana abilities
  (Clarion Conqueror) or the abilities of an attached permanent; skipping steps or phases (only whole turns);
  "can't draw more than one card / cast more than one spell each turn"; layer-6 timestamp shortcuts (attaching
  doesn't give a new timestamp, CR 613.7e; dependency loops, CR 613.8b).
- Damage and combat: dividing damage among targets as the spell is cast (CR 601.2d); blocking an
  additional creature or any number; lure ("all creatures able to block it do so"); "becomes blocked by" a
  filter; damage modification tied to one player (Lightning, Army of One); damage choices follow a fixed
  order (redirect, prevent, multiply, add) instead of the affected player's choice (CR 616.1).

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
