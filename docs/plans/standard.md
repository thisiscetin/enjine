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

## Progress (as of 2026-11-10)

This is the project's single progress document: where the Standard program
stands and what is pending.

**Done and on `main`:**
- Mechanics round 1 (6 builders) and round 2 (6 builders) are merged: 62 groups of
  mechanics and card shapes, from earthbend and saddle to Paradigm, Meld, gift,
  divided damage and ending the turn. See "Closed since the census" below.
- 586 real Standard cards are written in the DSL in `spec/fixtures/cards/real/`
  (all 14 sets, every card type), each with a scenario spec, and they pass
  `enjine --verify`.
- `enjine --verify DIR` (`Enjine::Verify`) checks any folder of card JSON:
  validation, rules-monitored play, and which cards were used.
- The caller API guide (`docs/guides/api.md`); the CLI passes priority for you when
  passing is the only choice and shows whose turn and which step it is.
- Gate: 1888 specs, ~99.5% line / ~91.5% branch coverage, RuboCop clean, fuzz
  and CI green (CI uses the latest Ruby 4.0.x).
- By the census, Star Trek, Reality Fracture, Avatar, Spider-Man and Aetherdrift
  have no known gaps; the other nine sets have 13 single-card gaps between them
  (tables below).

**In progress: round 3 ("known gaps").** It stopped at the usage limit before
any branch was gated or merged. The work is committed on four local branches
(worktrees in `.claude/worktrees/`):

| Branch | Area | Covers |
| --- | --- | --- |
| `worktree-wf_e8880e22-5ec-1` | casting and permissions | Raubahn, Nita, Bilbo (Thief in the Night), Gwen Stacy, Hama, Molten Exhale, Celestial Reunion, Key to the Side-Door, Ninja Teen, Baron Zemo, the gift trigger |
| `worktree-wf_e8880e22-5ec-2` | zones and loops | "repeat this process" (Sin), exile until total mana value (Improvisation Capstone), "exiled with" targets (The Darkness Crystal, Borg Cube), change the target (Redirect Lightning), Nth-counter trigger (Death to Our Enemies), "if it was attacking" (Desculpting Blast), meld mana value, hideaway, earthbend cleanup |
| `worktree-wf_e8880e22-5ec-3` | statics and combat (least complete) | granter tap cost (Fishing Pole), chosen-color hexproof (Mondo Gecko), "attacks alone", sized tokens, "can't become untapped"; still to do: Spider-Punk's granted riot, Ghalta, Storm, Chandra, Flameshaper |
| `worktree-wf_e8880e22-5ec-4` | rules correctness | entering attacking a planeswalker (508.4), choosing the order of damage replacements (616.1), prevention follow-ups for unpreventable damage (615.12), new targets firing ward and becomes-target triggers, revalidating divided spells, "a source of your choice" (609.7), ability last known information |

To finish it: each branch gets completed and gated, then the branches are merged
one at a time, the full gate plus fuzz and `--verify` runs, and the tables below
are recounted.

**Pending after round 3:**
1. **Per-set verification.** The census checked one example card per gap per set,
   not every card. For each set, write every card in the DSL outside the
   repository and run `enjine --verify` on it; any card that can't be written is a
   new gap and goes into another round. Then fill the README "Set support" table
   with ✓.
2. **Docs cleanup.** Reorganize `docs/guides/card-data-format.md` by concept
   (sections 4.19 to 4.29 grew one per merge); make `SUPPORTED.md` a compact
   index; shorten the README; check DESIGN, ARCHITECTURE and the guides against
   the code; decide whether the informational `rules_text` field stays in the DSL,
   the views and the example cards.
3. The remaining "Still open" items at the end of this file that no Standard card
   needs (lure, blocking several creatures, rad counters, 613.8 dependency loops)
   stay deferred until a card needs them.

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
| 2 | Reality Fracture | 2026-10-02 | 2029 (est.) | supported |
| 3 | The Hobbit | 2026-08-14 | 2029 (est.) | 2 gaps |
| 4 | Marvel Super Heroes | 2026-06-26 | 2029 (est.) | 2 gaps |
| 5 | Secrets of Strixhaven | 2026-04-24 | 2029 (est.) | 2 gaps |
| 6 | Teenage Mutant Ninja Turtles | 2026-03-06 | 2029 (est.) | 1 gap |
| 7 | Lorwyn Eclipsed | 2026-01-23 | 2029 (est.) | 1 gap |
| 8 | Avatar: The Last Airbender | 2025-11-21 | 2028 (est.) | supported |
| 9 | Spider-Man | 2025-09-26 | 2028 (est.) | supported |
| 10 | Edge of Eternities | 2025-08-01 | 2028 (est.) | 1 gap |
| 11 | Final Fantasy | 2025-06-13 | 2028 (est.) | 2 gaps |
| 12 | Tarkir: Dragonstorm | 2025-04-11 | 2028 (est.) | 1 gap |
| 13 | Aetherdrift | 2025-02-14 | 2028 (est.) | supported |
| 14 | Foundations | 2024-11-15 | 2029 (est.) | 1 gap |

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
  once or twice in samples and not listed below: controlling another player's
  turn (CR 724), granted loyalty abilities, "attacks alone" triggers and pile
  splitting. (Deck-construction exceptions, CR 100.2a, odd/even choices and ward
  with a non-mana cost were also seen and are now supported.)
- Ability words (landfall, threshold, raid, …) are not gaps in themselves; only
  what they need is listed. Sagas, Spacecraft/station, Planets, Equipment, Auras,
  modal spells, hybrid `{R/G}` mana, planeswalkers and legendary permanents
  are supported.
- A set's **Status** in the table above is its number of distinct gaps, or
  "supported" when none is left. Gaps closed since the census are listed under
  "Closed since the census" at the end of this section.

**Gaps left across all sets** (each now needed by about one card):

| Mechanic | CR | Sets | Example |
| --- | --- | --- | --- |
| Discard cost matched against your permanents ("same name as a legendary permanent you control") | 118.3, 701.9a | hob | Key to the Side-Door |
| Casting a spell from your graveyard as an effect ("you may cast an artifact, instant, or sorcery spell from your graveyard") | 601.2a, 608.2g | hob | Bilbo, Thief in the Night |
| Trigger on the Nth counter of a kind ("when the fourth plan counter is put on this") | 122.6, 603.2 | msh | Death to Our Enemies |
| Exile any number of graveyard cards as a cost, by mana symbols among them, then cast copies | 118.3, 707.12 | msh | Baron Helmut Zemo |
| Exile cards until their total mana value is N or greater | 406.1, 608.2c | sos | Improvisation Capstone |
| Cast trigger on a spell you don't own | 603.2, 108.3 | sos | Nita, Forum Conciliator |
| Hexproof from a color chosen on resolution | 702.11d | tmt | Mondo Gecko |
| A creature type chosen as part of an optional behold cost | 701.4, 601.2b | ecl | Celestial Reunion |
| Condition on a returned permanent's last known combat status ("if it was attacking") | 608.2h, 506.4 | eoe | Desculpting Blast |
| "Repeat this process" loops | 608.2c | fin | Sin, Spira's Punishment |
| Target filter: a card exiled with this permanent | 607.2a, 115.1 | fin | The Darkness Crystal |
| Flash that depends on an optional cost ("as though it had flash if you behold a Dragon") | 601.3c, 702.8 | tdm | Molten Exhale |
| A granted ability's cost that taps the granting permanent ("Tap Fishing Pole") | 602.2b, 607.1 | fdn | Fishing Pole |

### Star Trek (trk) — supported

311 cards.

No listed gap remains.

### Reality Fracture (fra) — supported

285 cards. No listed gap remains: last turn's history, behold or pay, restrictions on casting
the spell itself and type changes with a base P/T are written as in 4.24, 4.25, 4.27 and 4.28.

### The Hobbit (hob) — 2 gaps

193 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Discard cost matched against your permanents ("same name as a legendary permanent you control") | 118.3, 701.9a | 1 | Key to the Side-Door |
| Casting a spell from your graveyard as an effect (the exile-instead rider itself is supported) | 601.2a, 608.2g | 1 | Bilbo, Thief in the Night |

### Marvel Super Heroes (msh) — 2 gaps

281 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Trigger on the Nth counter of a kind (divided damage on the reflexive trigger is supported) | 122.6, 603.2 | 1 | Death to Our Enemies |
| Exile any number of graveyard cards as a cost, by mana symbols among them, then cast copies | 118.3, 707.12 | 1 | Baron Helmut Zemo |

### Secrets of Strixhaven (sos) — 2 gaps

271 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Exile cards until their total mana value is N or greater (paradigm itself is supported) | 406.1, 608.2c | 1 | Improvisation Capstone |
| Cast trigger on a spell you don't own (the exile-instead rider is supported) | 603.2, 108.3 | 1 | Nita, Forum Conciliator |

### Teenage Mutant Ninja Turtles (tmt) — 1 gap

195 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Hexproof from a color chosen on resolution | 702.11d | 1 | Mondo Gecko |

### Lorwyn Eclipsed (ecl) — 1 gap

273 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| A creature type chosen as part of an optional behold cost (behold or pay is supported) | 701.4, 601.2b | 1 | Celestial Reunion |

### Avatar: The Last Airbender (tla) — supported

286 cards. No listed gap remains (Hama, the Bloodbender's cast permission is under "Still open" below).

### Spider-Man (spm) — supported

193 cards. No listed gap remains (Spider-Man 2099 is written with `cast_restriction`, `turns_taken`
and `lands_played_this_turn`).

### Edge of Eternities (eoe) — 1 gap

266 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Condition on a returned permanent's last known combat status (`can_block_only` is supported) | 608.2h, 506.4 | 1 | Desculpting Blast |

### Final Fantasy (fin) — 2 gaps

312 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| "Repeat this process" loops | 608.2c | 1 | Sin, Spira's Punishment |
| Target filter: a card exiled with this permanent (the dies-to-exile replacement is supported) | 607.2a, 115.1 | 1 | The Darkness Crystal |

### Tarkir: Dragonstorm (tdm) — 1 gap

276 cards. The census listed Stalwart Successor under suspend; it has no suspend (Taigam, Master
Opportunist is the set's suspend card, and is supported).

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| Flash that depends on an optional cost ("as though it had flash if you behold a Dragon") | 601.3c, 702.8 | 1 | Molten Exhale |

### Aetherdrift (dft) — supported

276 cards. No listed gap remains.

### Foundations (fdn) — 1 gap

517 cards.

| Missing mechanic | CR | ~Cards | Example |
| --- | --- | ---: | --- |
| A granted ability's cost that taps the granting permanent (the `granter` selector covers effects) | 602.2b, 607.1 | 1 | Fishing Pole |

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
| Choosing between costs ("behold a Goblin or pay {2}"), optional additional costs, paying costs while resolving, ward with a non-mana cost, gift, "you may behold a Jace; if you don't, it enters tapped" | 601.2b, 118.8b, 118.12, 702.21a, 702.174 | cost `one_of`, decision `choose_cost_option`; `additional_cost` `optional`; `pay` / `counter_unless_pays` `cost`; `ward` `cost`; cost `get_counters`; ability `gift`; `enters_tapped_unless_behold`; `spells_have` (4.24) |
| Divide damage among targets; "can't cast this spell unless"; which sources paid the mana ("mana from a Treasure"), mana spent compared with an amount; mana spendable only on spells not cast from hand; exile-instead replacement for spells cast via an effect; "Activate only if" on mana abilities | 601.2d, 601.3, 601.2h, 106.6, 614.1a, 602.5b | `divide` + effect `distribute_damage`; ability `cast_restriction`; amounts `turns_taken`, `mana_value`, `greatest_toughness`; `mana_spent` `from`; `spend_only` `from` / `not_from`; `exile_instead`; mana `only_if` (4.25) |
| Block restrictions; attack triggers on total power and "for the first time each turn"; attack restriction for an added combat; damage modification for sources that entered this turn or tied to one player; damage isn't removed during cleanup; prevention with a follow-up, a chosen source or a duration; dies-to-exile with a follow-up; excess damage in a fight; ending the turn | 509.1b, 508.1c, 616, 514.2, 615.5, 615.8, 611.2b, 614.1a, 120.4a, 725 | `can_block_only`; triggers `attacks` / `player_attacks`; `additional_phases` `attackers`; filter `entered_this_turn`; effect `damage_replacement`; keyword `keeps_damage`; `prevent_damage` `then` / `chosen_source` / `next_time` / `duration`; `exile_if_dies` `then`; effect `end_the_turn` (4.26) |
| Statics that set card types or the name; protection from each opponent; station, crew and saddle using toughness or "as though its power were 2 greater"; "for as long as you control this"; "activated abilities can't be activated" including mana abilities; granted abilities that refer to the granting permanent; two "as this enters" choices; type changes depending on each object | 205.1a, 612.8, 702.16k, 702.184a, 611.2b, 602.5, 607.1a, 614.12, 613.7e | static `set_types`, `name`; `protection_from` `"each_opponent"`; ability `tapping_power`; duration `while_you_control_source`; keyword flag `abilities_cant_be_activated`; selector `"granter"` (4.27) |
| What happened last turn; playing a land from anywhere (trigger, amount); "enters from exile"; amount "this way" through a "may"; "those creatures"; copying the ability that triggered; boast and teamwork-tap triggers; choosing new targets; granting cascade to spells; exchange of targets that share a card type; searching for different names; coin-flip replacements; dice | 120.2b, 305.1, 608.2c, 707.10, 702.142b, 115.7d, 701.12b, 705.3, 706 | amount `noncombat_damage_last_turn`; trigger `plays_land`, `lands_played_this_turn`; selectors `{"triggering": "targets" \| "ability"}`; trigger `ability_triggers`; effect `choose_new_targets`; ability `spell_keywords`; `shares_type_with`; `different_names`; `first_flips_win`; effect `roll_dice` (4.28) |
| Paradigm, foretell, suspend, hideaway, devour, meld, endure with a computed N, proliferate X times by planeswalker types | 702.192, 702.143, 702.62, 702.75, 702.82, 701.42, 713, 701.63 | keywords and abilities of the same names; effects `meld`, `suspend`; amount `distinct_planeswalker_types` (4.29) |

Still open in these areas (not yet counted as gaps above, since the census didn't
separate them):
- Costs: "Ward—Pay life equal to its power" (a computed `pay_life`, Raubahn), "whenever a player gives a gift"
  (CR 702.174c), more than one optional cost announced per spell (teamwork still marks the spell kicked), and
  "change the target of target spell" (Redirect Lightning; `choose_new_targets` lets the player keep it).
- "Can't crew Vehicles" (CR 702.122d); granting `tapping_power` through `become`.
- Casting a card "by waterbending {X}" rather than paying its mana cost, and cast permissions that last "for as
  long as you control" a source (Hama, the Bloodbender; Gwen Stacy).
- Granting flashback, harmonize, mayhem, web-slinging or sneak to other cards (Ninja Teen); "cost {N} less"
  for spells cast from anywhere other than your hand (the remaining "Spells cast from anywhere other than
  hand" rows); "as though exhaust abilities haven't been activated".
- Amass or empower by another player, and triggers on blighting, firebending or conniving.
- Casting a card transformed (disturb, CR 712.8a), convert (CR 701.28), day/night (CR 702.145), the mana value
  of a transformed back face (CR 712.6d) and of a melded permanent (CR 713.5c).
- A type change by a resolved effect that replaces the other types or lasts "until your next turn".
- "Whenever you cycle or discard a card" triggering only once for a cycled card
  (CR 702.29d); amounts from another leaving object's last known counters; "a card put
  into your graveyard from anywhere this turn" as a target filter.
- A card spec (library search) matching the chosen type, and a static that grants
  keywords to creatures filtered by keywords (layer-6 dependency, CR 613.8).
- Set mechanics: granting riot to other permanents (Spider-Punk: statics that would grant an "as this enters"
  choice are not read before it enters, CR 614.12) and the choice of hybrid half when a power-up cost is
  reduced (CR 118.7e: the half the cost needs is taken).
- Rules and statics: rad counters' inherent trigger (CR 729); skipping steps or phases (only whole turns);
  "can't draw more than one card / cast more than one spell each turn"; "can't become untapped"
  (Spider-Woman); dependency ordering and loops (CR 613.8).
- Damage and combat: blocking an additional creature or any number; lure ("all creatures able to block it do
  so"); "becomes blocked by" a filter; a source chosen from the command zone (CR 609.7a); damage choices
  follow a fixed order (redirect, prevent, multiply, add; statics before resolved effects) instead of the
  affected player's choice (CR 616.1); prevention follow-ups when the damage can't be prevented (CR 615.12).

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
