# Mechanics coverage checklist

Rules version: Comprehensive Rules effective 2026-09-25.

A source-backed checklist of every game mechanic a fully rules-accurate
**two-player** engine must eventually support, organised by the Comprehensive
Rules (CR) section structure. Each line gives the rule number, a one-line
description and a suggested milestone. This is a planning document; it is not
generated, and it does not claim anything is implemented (see `SUPPORTED.md`
for that).

## Priority: Standard first

The project builds mechanics in this order:

1. **Evergreen mechanics.** These are on cards in every Standard set: the ★ keywords
   (flying, first strike, deathtouch, trample, lifelink, vigilance, reach, menace,
   ward, hexproof, indestructible, defender, double strike), triggered abilities,
   static abilities and layers, replacement effects, tokens, auras and equipment,
   sacrifice, scry/surveil, mill, and X costs.
2. **Mechanics on cards currently legal in Standard.** Check a set's mechanics
   against the current Standard rotation before scheduling it.
3. **Mechanics that exist only on cards no longer in Standard.** These are
   low priority. They stay in this checklist for completeness, but they aren't
   scheduled.

The ★ marks below are about how common a mechanic is. Within each milestone,
build ★ items that appear in current Standard first.

## Sources

All rule numbers and wording below were checked against the **plain-text** CR,
fetched 2026-11-08:

- Pinned version (used for every rule number here):
  `https://media.wizards.com/2026/downloads/MagicCompRules%2020260925.txt`
  ("These rules are effective as of September 25, 2026.")
- PDF of the same version (downloaded, not parsed; the TXT was used):
  `https://media.wizards.com/2026/downloads/MagicCompRules%2020260925.pdf`
- Rules index: `https://magic.wizards.com/en/rules`. **As of 2026-11-08 it links
  a newer CR, effective 2026-11-06**
  (`https://media.wizards.com/2026/downloads/MagicCompRules%2020261106.txt`).
  It was diffed against the pinned version at heading level only (see below).

### Version drift: 2026-09-25 → 2026-11-06

The newer CR adds a section and renumbers the rest of section 7. Anyone
reading a newer CR must translate 7xx numbers:

| 2026-09-25 (pinned) | 2026-11-06 |
| --- | --- |
| (none) | 713 Meld Cards (new section) |
| 713 Substitute Cards … 722 Preparation Cards | 714 … 723 (each +1) |
| 723 Controlling Another Player … 733 Handling Illegal Actions | 724 … 734 (each +1) |
| (none) | 701.72 Assimilate (new keyword action) |
| (none) | 702.196 Beam me up (new keyword ability) |

Only headings were diffed. Subrule wording changes inside the newer CR were
**not** checked.

## Milestone tags

| Tag | Scope |
| --- | --- |
| **M1** | Skeleton: game setup, turns/steps, priority, lands, mana, SBAs, basic combat |
| **M2** | Stack: casting (601.2), targeting, activated and triggered abilities, resolution |
| **M3** | Continuous effects: layers, replacement and prevention, counters, Auras and Equipment, copy |
| **M4** | Keywords and planeswalkers |
| **M5** | Long tail: rare or old mechanics, unusual card frames |
| **OOS** | Out of scope for a two-player engine: multiplayer-only, casual variants, Un-/Attraction-only |

★ = **priority**, meaning one of the roughly 40 most common evergreen or
deciduous mechanics. Build these first within their milestone. The ★ marks
appear on the 701/702 keyword rows; the priority mechanics that have no keyword
number are listed under "Other priority mechanics" after the keyword tables.
The section 1–7 rules tables carry no ★, because everything tagged M1 or M2
there is on the critical path regardless.

---

## Engine-architecture implications

These rules cut across every mechanic. All numbers were checked in the
2026-09-25 text.

1. **400.7: a zone change creates a new object** "with no memory of, or relation to, its previous existence" (the exceptions are listed in 400.7a–). Object identity has to be per-zone-instance, not per-card. Last-known information (LKI) is needed for 603.10 look-back triggers and for 704.8.
2. **110.5: permanent status** (tapped/untapped, flipped/unflipped, face up/face down, phased in/out). Status is not a characteristic (110.5a) and only permanents have it (110.5d).
3. **117.3–117.5: the priority loop.** Before any player would receive priority, the engine performs SBAs repeatedly as single simultaneous events, then puts triggered abilities on the stack, then repeats until stable (117.5). The active player gets priority after a resolution (117.3b). If all players pass in succession, the top of the stack resolves, or the step ends if the stack is empty (117.4). Mana in the pool is announced on a pass (117.3d).
4. **601.2a–i: casting is a transaction.** Propose: move the card to the stack, choose modes, splice, and alternative/additional costs (a–b), then targets (c), then division (d). Legality check (e). Determine the locked-in total cost (f). Activate mana abilities (g). Pay (h): costs with no random element and no library-to-public-zone movement go first, then the rest, and partial payments are not allowed. The spell becomes cast and cast-triggers fire (i). Activation (602.2) mirrors this.
5. **733.1 (not 732): illegal-action reversal.** "The entire action is reversed and any payments already made are canceled. No abilities trigger…" 601.2e points here. In the 2026-09-25 CR, 732 is *Taking Shortcuts*. (In the 2026-11-06 CR these become 734 and 733.) The engine needs snapshot/rollback around every cast, activation and attack/block declaration.
6. **605.1a: mana-ability classification (changed in Aug 2026).** An activated ability is a mana ability only if it has no target, could add mana, is not a loyalty ability, **and "its cost and effect don't move any card to or from a library."** Classification must apply this full test, not just "adds mana". 605.3a: mana abilities can be activated in the middle of casting or resolving.
7. **603.3b: trigger ordering in APNAP order.** Each player puts the triggers they control on the stack in the order they choose, in APNAP order (101.4). 603.10 lists the "look back in time" triggers (leaves-the-battlefield and similar). 603.7 covers delayed triggers. 603.4 covers intervening-"if" clauses, which are checked both on trigger and on resolution.
8. **608.2b: target re-check on resolution.** A spell or ability with no legal targets left doesn't resolve. If only some targets are illegal, it resolves and does nothing to the illegal ones.
9. **613: layers.** 613.1a–g give layers 1–7. 613.2 gives the layer-1 sublayers (1a copiable effects, including merges; 1b face-down characteristics). 613.3: within layers 2–6, characteristic-defining abilities (CDAs) apply first, then timestamp order. 613.4a–d give sublayers 7a–7d (CDA, set, modify including counters, switch). 613.6: an effect that starts applying keeps applying to the same set of objects. 613.7a–n are the timestamp rules (attachment, face-up, transform and stickers all refresh the timestamp). **613.8: dependency** overrides timestamp order, and dependency loops fall back to timestamp. Characteristics must be computed by a pure function over base values plus the active effects. Never mutate the base object.
10. **614/615/616: replacement and prevention.** These apply as events happen and are not locked in (614.1). 614.12 covers ETB-modifying replacements, which must be checked against the permanent as it would exist on the battlefield. **616.1**: the affected object's controller (or its owner, if it has no controller) or the affected player chooses the order, in a fixed priority: a self-replacement effect first (616.1a), then control-of-ETB effects (b), then copy-as-ETB effects (c), then back-face-up ETB effects (d), then any (e). The process repeats over the effects that still apply (616.1f). Each replacement effect applies at most once to a given event.
11. **703.4: turn-based actions** (phasing, day/night, untap, draw, lore counters, declarations, damage, cleanup). **703.4q / 500.5**: mana pools empty at the end of each step and phase.
12. **704.7 / 704.8: SBAs are simultaneous.** A single replacement effect replaces all identical simultaneous SBA results (704.7). LKI for permanents that leave through SBAs comes from before any of the simultaneous SBAs were performed (704.8).
13. **514.3a: the cleanup step repeats.** If SBAs happen or triggers are waiting during cleanup, players get priority and another cleanup step follows.
14. **116.2: special actions** don't use the stack and come in twelve kinds (see §1). The action model needs "play land", "turn face up" and so on as first-class actions alongside cast and activate.
15. **Designations and player-level state** (monarch 725, initiative 726, day/night 731, speed 702.179, city's blessing 702.131, Ring-bearer 701.54, enduring story 702.195, rad counters 728). These need a general per-player and per-game designation store, not ad-hoc flags.

---

## 1. Game Concepts (100–123)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 100 | General; two-player vs multiplayer (100.1a/b); deck construction minimums | M1 |
| 101 | Golden rules: a card's text overrides the rules; "can't" beats "can"; APNAP order (101.4) | M1 |
| 102 | Players, opponents, teammates | M1 |
| 103 | Starting the game: shuffle, choose who plays first, opening hand, mulligans, the first player skips their first draw | M1 |
| 104 | Ending the game: win, lose, draw, concede | M1 |
| 105 | Colors, colorless, multicolor | M1 |
| 106 | Mana: types, the mana pool, mana emptying, restrictions on mana use | M1 |
| 107 | Numbers and symbols: X, mana symbols (hybrid, Phyrexian, snow, {C}), {T}/{Q}, loyalty symbols, {E} energy, and others | M1–M3 |
| 108 | Cards: owner, oracle text | M1 |
| 109 | Objects: characteristics, controller | M1 |
| 110 | Permanents and status (110.5) | M1 |
| 111 | Tokens, including predefined tokens (Treasure, Clue, Food, Blood, Incubator and others, 111.10) | M2 |
| 112 | Spells | M2 |
| 113 | Abilities: spell, activated, triggered, static; where abilities function | M2 |
| 114 | Emblems | M4 |
| 115 | Targets: legal targets, changing targets, "any target" | M2 |
| 116 | Special actions (twelve, 116.2a–m): | |
| 116.2a | Play a land | M1 |
| 116.2b | Turn a face-down creature face up | M5 |
| 116.2c | Take a later action that an effect allows (ending an effect or stopping a delayed trigger) | M5 |
| 116.2d | Ignore a static ability's effect for a duration | M5 |
| 116.2e | Circling Vultures discard | M5 |
| 116.2f | Exile a card with suspend from hand | M5 |
| 116.2g | Pay {3} to put the companion into hand | M5 |
| 116.2h | Foretell (pay {2}, exile face down) | M5 |
| 116.2i | Roll the planar die (Planechase) | OOS |
| 116.2j | Turn a conspiracy face up | OOS |
| 116.2k | Plot (exile from hand) | M5 |
| 116.2m | Pay an unlock cost for a locked half of a split permanent (Rooms) | M5 |
| 117 | Timing and priority | M1 |
| 118 | Costs: mana, additional (118.8), alternative (118.9), cost increases and reductions, "if you do" (118.12) | M2 |
| 119 | Life: gain, loss, paying life | M1 |
| 120 | Damage: to players, creatures, planeswalkers and battles; combat vs noncombat; damage results | M1 |
| 121 | Drawing a card | M1 |
| 122 | Counters: +1/+1 and -1/-1 (122.1a), keyword counters (122.1b), shield (c), stun (d), loyalty (e), poison (f), defense (g), finality (h), rad (i), hone (j) | M3 |
| 123 | Stickers (Un-/Alchemy-adjacent) | OOS |

## 2. Parts of a Card (200–213)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 201 | Name; "named" and same-name checks | M1 |
| 202 | Mana cost, mana value, color derived from cost | M1 |
| 203 | Illustration (no rules meaning) | n/a |
| 204 | Color indicator | M3 |
| 205 | Type line: card types (205.2a), subtypes (205.3), supertypes basic/legendary/ongoing/snow/world (205.4a) | M1 |
| 206 | Expansion symbol (rarely relevant) | n/a |
| 207 | Text box: rules text, ability words, flavor | M2 |
| 208 | Power/toughness, including `*` CDAs | M1 |
| 209 | Loyalty | M4 |
| 210 | Defense (battles) | M4 |
| 211 | Hand modifier (Vanguard) | OOS |
| 212 | Life modifier (Vanguard) | OOS |
| 213 | Information below the text box | n/a |

## 3. Card Types (300–315)

| Rule | Type | What the engine needs | Milestone |
| --- | --- | --- | --- |
| 300 | General | Multiple card types; type-changing effects | M1 |
| 301 | Artifact | Permanent cast at sorcery speed; Equipment (301.5), Fortification, Vehicle; predefined artifact tokens | M1 (Equipment M3) |
| 302 | Creature | P/T, combat, summoning sickness (302.6: no {T}/{Q} abilities and no attacking unless controlled continuously since the start of the controller's most recent turn) | M1 |
| 303 | Enchantment | Auras (303.4a–m: targeting, attachment legality, ETB without casting); Sagas, Classes, Cases, Roles, Rooms | M1 (Auras M3) |
| 304 | Instant | Cast any time you have priority | M2 |
| 305 | Land | Land play (305.2), basic land types granting mana abilities (305.6), land-type setting (305.7), land + other type can only be played as a land (305.9) | M1 |
| 306 | Planeswalker | Loyalty (306.5a–d), enters with loyalty counters (replacement effect), loyalty abilities (606), can be attacked, damage removes loyalty | M4 |
| 307 | Sorcery | Main phase, empty stack | M2 |
| 308 | Kindred | Has another card type; gets creature types | M5 |
| 309 | Dungeon | Command zone, venture marker, room abilities (via venture / initiative) | M5 |
| 310 | Battle | Defense (310.4), protector, Siege; attackable; SBAs 704.5v–y | M5 |
| 311 | Plane | Planechase | OOS |
| 312 | Phenomenon | Planechase | OOS |
| 313 | Vanguard | Vanguard | OOS |
| 314 | Scheme | Archenemy | OOS |
| 315 | Conspiracy | Conspiracy Draft | OOS |

## 4. Zones (400–408)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 400 | General: public vs hidden zones; **400.7 new object on zone change**; owner's zones; simultaneous moves | M1 |
| 401 | Library: order, top/bottom, revealing, "draw from empty library" | M1 |
| 402 | Hand: hidden; maximum hand size | M1 |
| 403 | Battlefield | M1 |
| 404 | Graveyard: ordered, public | M1 |
| 405 | Stack: LIFO; what goes on it | M2 |
| 406 | Exile: face-up and face-down exile; "exiled with" links | M2 |
| 407 | Ante | OOS |
| 408 | Command zone: emblems, dungeons, (variant cards) | M4 |

## 5. Turn Structure (500–514)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 500 | General: phases and steps; mana empties (500.5); extra turns, phases and steps; skipping | M1 (extra turns M5) |
| 501 | Beginning phase | M1 |
| 502 | Untap step: phasing, day/night check, untap; no priority | M1 |
| 503 | Upkeep step | M1 |
| 504 | Draw step | M1 |
| 505 | Main phases (precombat/postcombat); land play; lore counters (703.4f) | M1 |
| 506 | Combat phase: defending player, attacking/blocking, removed from combat; declare-blockers and damage steps skipped if there are no attackers | M1 |
| 507 | Beginning of combat step | M1 |
| 508 | Declare attackers: 508.1a–m (legality, choosing a player/planeswalker/battle, restrictions and requirements, banding, tapping, attack costs, triggers) | M1 |
| 509 | Declare blockers: 509.1a–i (restrictions and requirements, block costs, blocked/unblocked) | M1 |
| 510 | Combat damage: no damage assignment order; the controller of a blocked creature divides its damage among its blockers as they choose (510.1c), first strike/double strike creates a second damage step, simultaneous dealing | M1 |
| 511 | End of combat step | M1 |
| 512 | Ending phase | M1 |
| 513 | End step; "at the beginning of the next end step" delayed triggers | M1 |
| 514 | Cleanup: discard to hand size, remove damage, end "until end of turn" effects, repeat if needed (514.3a) | M1 |

## 6. Spells, Abilities, and Effects (600–616)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 601.2a | Propose: move the card to the stack, apply characteristic-changing effects | M2 |
| 601.2b | Announce modes, splice, alternative/additional costs, X, hybrid/Phyrexian choices | M2 |
| 601.2c | Choose targets (including targets that depend on mode or kicker) | M2 |
| 601.2d | Divide/distribute among targets (at least 1 each) | M2 |
| 601.2e | Legality check, reversing via 733 if the spell is illegal | M2 |
| 601.2f | Determine the total cost (mana cost or alternative cost, plus additional costs, plus increases, minus reductions); locked in | M2 |
| 601.2g | Activate mana abilities | M2 |
| 601.2h | Pay costs in any order (costs with no random element and no library-to-public-zone movement first); no partial payment | M2 |
| 601.2i | The spell becomes cast; cast triggers; priority returns to the caster | M2 |
| 601.3 | Permission to cast (from hand by default; "may cast from X" effects) | M2 |
| 602 | Activating activated abilities; {T}/{Q} plus summoning sickness (602.5a); "activate only once each turn"/as a sorcery/as an instant (602.5b–e) | M2 |
| 603 | Triggered abilities: trigger events, APNAP ordering (603.3b), intervening "if" (603.4), zone-change triggers (603.6), delayed triggers (603.7), look-back (603.10), state triggers, reflexive triggers | M2 |
| 604 | Static abilities; characteristic-defining abilities (604.3) | M3 |
| 605 | Mana abilities: classification (605.1a/b, **includes the Aug 2026 library-movement exclusion**), no stack, activation mid-cast | M1 |
| 606 | Loyalty abilities: one per permanent per turn, sorcery timing (606.3) | M4 |
| 607 | Linked abilities ("exiled with", "the chosen X") | M3 |
| 608 | Resolving: target re-check (608.2b), following instructions in order, choices on resolution, a permanent spell becomes a permanent | M2 |
| 609 | Effects: general, "you may", "unless", undefined quantities | M2 |
| 610 | One-shot effects; effects that create delayed triggers or continuous effects | M2 |
| 611 | Continuous effects: from resolving spells (locked set) vs from static abilities (dynamic set); duration | M3 |
| 612 | Text-changing effects (layer 3) | M5 |
| 613 | Layers 1–7 with sublayers, CDAs first, timestamps (613.7), dependency (613.8) | M3 |
| 614 | Replacement effects: "instead" (614.1a), "skip" (b), "enters with/as" (c–d), "as turned face up" (e), self-replacement (614.15), ETB replacements (614.12) | M3 |
| 615 | Prevention effects: prevention shields, "prevent all", damage that can't be prevented | M3 |
| 616 | Ordering of replacement/prevention effects (616.1a–f) | M3 |

## 7. Additional Rules (700–733)

| Rule | Mechanic | Milestone |
| --- | --- | --- |
| 700 | General: modal spells (700.2), "choose one or more", "each", "you", "dies", "attacks alone", party, historic, "exactly" | M2 |
| 701 | Keyword actions (full list below) | — |
| 702 | Keyword abilities (full list below) | — |
| 703 | Turn-based actions (703.4a–q) | M1 |
| 704 | State-based actions (full list below) | M1 |
| 705 | Flipping a coin | M5 |
| 706 | Rolling a die | M5 |
| 707 | Copying objects: copiable values, copy-of-a-copy, "except" modifications, copying spells and choosing new targets, token copies | M3 |
| 708 | Face-down spells and permanents (morph, disguise, manifest, cloak, foretell exile); turning face up; revealing at end of game | M5 |
| 709 | Split cards (fuse, aftermath); **709.5 split permanents with locked/unlocked halves (Rooms)** | M5 |
| 710 | Flip cards | M5 |
| 711 | Leveler cards (level up) | M5 |
| 712 | Double-faced cards: transforming DFCs, modal DFCs, meld; which face is up in each zone | M4 (transform/MDFC) |
| 713 | Substitute cards (checklist proxies for DFCs) | M5 |
| 714 | Saga cards: lore counters, chapter triggers, sacrifice SBA | M4 |
| 715 | Adventurer cards: cast as the Adventure, exile, cast the creature later | M4 |
| 716 | Class cards: level bars | M5 |
| 717 | Attraction cards | OOS |
| 718 | Prototype cards | M5 |
| 719 | Case cards (solved) | M5 |
| 720 | Omen cards: two-part frame; cast normally or as an Omen; an Omen spell is shuffled into the library on resolution (720.3d) | M5 |
| 721 | Station cards: station symbols `{N+}` grant abilities/P/T at a charge-counter threshold | M5 |
| 722 | **Preparation cards** (new): inset "prepare spell"; prepared/unprepared designation; on becoming prepared, a copy is created in exile that may be cast (722.3a–c) | M5 |
| 723 | Controlling another player (Mindslaver) | M5 |
| 724 | Ending turns and phases (Time Stop, Sundial) | M5 |
| 725 | The monarch | M5 |
| 726 | The initiative (Undercity dungeon) | M5 |
| 727 | Restarting the game (Karn Liberated) | M5 |
| 728 | Rad counters (inherent player trigger) | M5 |
| 729 | Subgames (Shahrazad) | M5 |
| 730 | Merging with permanents (mutate) | M5 |
| 731 | Day and night | M5 |
| 732 | Taking shortcuts (loop shortcuts, conditional priority passes) | M2 (engine/UI policy) |
| 733 | Handling illegal actions: reversal and rollback (733.1) | M2 |

### State-based actions (704.5a–aa; the letters skip l and o)

| Rule | SBA | Milestone |
| --- | --- | --- |
| 704.5a | A player with 0 or less life loses | M1 |
| 704.5b | A player who drew from an empty library since the last check loses | M1 |
| 704.5c | 10+ poison counters: the player loses | M4 |
| 704.5d | A token in a zone other than the battlefield ceases to exist | M2 |
| 704.5e | A copy of a spell off the stack, or a copy of a card outside the stack/battlefield, ceases to exist | M3 |
| 704.5f | A creature with toughness 0 or less goes to the graveyard (can't be regenerated) | M1 |
| 704.5g | Lethal marked damage destroys the creature (can be regenerated) | M1 |
| 704.5h | Damage from a deathtouch source destroys the creature | M4 |
| 704.5i | A planeswalker with 0 loyalty goes to the graveyard | M4 |
| 704.5j | Legend rule | M1 |
| 704.5k | World rule | M5 |
| 704.5m | An Aura attached illegally or to nothing goes to the graveyard | M3 |
| 704.5n | Equipment/Fortification attached illegally becomes unattached | M3 |
| 704.5p | A battle/creature, or another non-Aura/Equipment/Fortification permanent, attached to something becomes unattached | M3 |
| 704.5q | +1/+1 and -1/-1 counters annihilate | M3 |
| 704.5r | "Can't have more than N counters" is enforced | M5 |
| 704.5s | A Saga at or past its final chapter (with no chapter ability pending) is sacrificed | M4 |
| 704.5t | A dungeon whose venture marker is on its bottom room (with no room ability pending) is removed | M5 |
| 704.5u | Space sculptor sector designations | OOS |
| 704.5v | A Siege battle with 0 defense (no pending trigger from it) goes to the graveyard | M5 |
| 704.5w | A non-Siege battle with 0 defense goes to the graveyard | M5 |
| 704.5x | A battle with no protector gets one chosen | M5 |
| 704.5y | A battle with an illegal protector is reassigned or goes to the graveyard | M5 |
| 704.5z | Multiple Roles from the same controller on one permanent: only the newest stays | M5 |
| 704.5aa | A controller of a start-your-engines! permanent who has no speed gets speed 1 | M5 |
| 704.6a–f | Variant SBAs (Two-Headed Giant, Commander, Archenemy, Planechase) | OOS |

---

## Keyword actions (701.2–701.71)

701.1 is the general rule. Every numbered keyword action in the 2026-09-25 CR is listed.

| Rule | Action | Description | Milestone |
| --- | --- | --- | --- |
| 701.2 | Activate | Put an activated ability on the stack and pay its costs | M2 |
| 701.3 | Attach | Move an Aura/Equipment/Fortification onto an object or player | M3 ★ |
| 701.4 | Behold | Reveal a qualifying card from hand or choose a qualifying permanent | M5 |
| 701.5 | Cast | Take a spell to the stack and pay its costs | M2 |
| 701.6 | Counter | Remove a spell or ability from the stack without it resolving | M2 ★ |
| 701.7 | Create | Put tokens onto the battlefield | M2 ★ |
| 701.8 | Destroy | Move a permanent from the battlefield to its owner's graveyard (replaceable by regenerate/indestructible) | M1 ★ |
| 701.9 | Discard | Move a card from hand to the graveyard | M1 ★ |
| 701.10 | Double | Double P/T (a modify effect, layer 7c), life, counters, mana, or damage | M5 |
| 701.11 | Triple | As with double, ×3 | M5 |
| 701.12 | Exchange | Swap life totals, control, zones or values; all-or-nothing | M5 |
| 701.13 | Exile | Move an object to exile | M1 ★ |
| 701.14 | Fight | Each creature deals damage equal to its power to the other | M2 ★ |
| 701.15 | Goad | A goaded creature attacks each combat, and attacks a player other than the goader if able | M5 |
| 701.16 | Investigate | Create a Clue token | M2 ★ |
| 701.17 | Mill | Put the top N cards of the library into the graveyard | M2 ★ |
| 701.18 | Play | Play a land or cast a spell | M1 |
| 701.19 | Regenerate | Next-destruction replacement: tap, remove damage, remove from combat | M3 |
| 701.20 | Reveal | Show a card to all players | M2 |
| 701.21 | Sacrifice | The controller moves a permanent to its owner's graveyard (not destruction) | M1 ★ |
| 701.22 | Scry | Look at the top N; any number to the bottom, the rest on top in any order | M2 ★ |
| 701.23 | Search | Look through a zone for matching cards (may fail to find) | M2 ★ |
| 701.24 | Shuffle | Randomize a library or face-down pile | M1 |
| 701.25 | Surveil | Look at the top N; any number to the graveyard, the rest on top | M2 ★ |
| 701.26 | Tap and Untap | Turn sideways or upright | M1 |
| 701.27 | Transform | Turn a DFC permanent to its other face | M4 ★ |
| 701.28 | Convert | Transform-equivalent wording for some DFCs (Transformers) | M5 |
| 701.29 | Fateseal | Scry an opponent's library | M5 |
| 701.30 | Clash | Reveal the top card, may bottom it, compare mana values | M5 |
| 701.31 | Planeswalk | Planechase only | OOS |
| 701.32 | Set in Motion | Archenemy only | OOS |
| 701.33 | Abandon | Archenemy only | OOS |
| 701.34 | Proliferate | Add one counter of each kind already present to any chosen permanents/players | M3 ★ |
| 701.35 | Detain | Until your next turn: can't attack/block, activated abilities can't be activated | M5 |
| 701.36 | Populate | Create a copy of a creature token you control | M5 |
| 701.37 | Monstrosity | If not monstrous, put N +1/+1 counters and become monstrous | M5 |
| 701.38 | Vote | Players vote among options (works in two-player) | M5 |
| 701.39 | Bolster | N +1/+1 counters on your creature with the least toughness | M5 |
| 701.40 | Manifest | Put a card onto the battlefield face down as a 2/2; turn face up if it's a creature | M5 |
| 701.41 | Support | +1/+1 counters on up to N other target creatures | M5 |
| 701.42 | Meld | Combine a meld pair into one oversized permanent | M5 |
| 701.43 | Exert | Doesn't untap during your next untap step | M5 |
| 701.44 | Explore | Reveal the top card; land → hand, otherwise a +1/+1 counter and the card may go to the graveyard | M4 |
| 701.45 | Assemble | Contraptions (Unstable; Steamflogger Boss) | OOS |
| 701.46 | Adapt | If no +1/+1 counters, put N | M5 |
| 701.47 | Amass | Create/grow an Army token with N +1/+1 counters | M5 |
| 701.48 | Learn | Rummage, or fetch a Lesson from outside the game | M5 |
| 701.49 | Venture into the Dungeon | Choose a dungeon from outside the game, move the venture marker, room trigger | M5 |
| 701.50 | Connive | Draw, discard; nonland discarded → +1/+1 counter | M5 |
| 701.51 | Open an Attraction | Attractions only | OOS |
| 701.52 | Roll to Visit Your Attractions | Attractions only | OOS |
| 701.53 | Incubate | Create an Incubator token with N +1/+1 counters | M5 |
| 701.54 | The Ring Tempts You | Choose a Ring-bearer; gain the next Ring ability level | M5 |
| 701.55 | Face a Villainous Choice | The player picks option A or B | M5 |
| 701.56 | Time Travel | Add/remove a time counter on each chosen permanent/suspended card | M5 |
| 701.57 | Discover | Exile until a nonland card with mana value ≤ N; cast it free or put it in hand | M5 |
| 701.58 | Cloak | Manifest with ward {2} | M5 |
| 701.59 | Collect Evidence | Exile graveyard cards with total mana value ≥ N (usually a cost) | M5 |
| 701.60 | Suspect | Designation: menace and can't block | M5 |
| 701.61 | Forage | Exile three cards from your graveyard or sacrifice a Food | M5 |
| 701.62 | Manifest Dread | Look at the top 2, manifest one, the other to the graveyard | M5 |
| 701.63 | Endure | Put N +1/+1 counters, or create an N/N Spirit token | M5 |
| 701.64 | Harness | Permanent becomes harnessed (enables ∞ abilities) | M5 |
| 701.65 | Airbend | Exile; the owner may cast it for {2} while exiled | M5 |
| 701.66 | Earthbend | Target land becomes a 0/0 haste creature with N +1/+1 counters and returns when it dies or is exiled | M5 |
| 701.67 | Waterbend | Pay a cost, tapping artifacts/creatures for generic mana | M5 |
| 701.68 | Blight | Put N -1/-1 counters on a creature you control | M5 |
| 701.69 | Heal | Remove damage marked on a permanent | M5 |
| 701.70 | Recruit | Draw, discard; nonland discarded → 1/1 Human Soldier token | M5 |
| 701.71 | Empower Jace | Create or choose a Jace planeswalker token and add N loyalty | M5 |
| *(701.72)* | *Assimilate* | *2026-11-06 CR only: gain control, +1/+1 counter, becomes a Borg artifact creature* | *M5 (not in pinned CR)* |

## Keyword abilities (702.2–702.195)

702.1 is the general rule. Every numbered keyword ability in the 2026-09-25 CR is listed.

| Rule | Ability | Description | Milestone |
| --- | --- | --- | --- |
| 702.2 | Deathtouch | Any damage from it to a creature is lethal; 1 damage counts as lethal when assigning | M4 ★ |
| 702.3 | Defender | Can't attack | M4 ★ |
| 702.4 | Double Strike | Deals both first-strike and regular combat damage | M4 ★ |
| 702.5 | Enchant | Restricts an Aura's targets and what it can be attached to | M3 ★ |
| 702.6 | Equip | `[Cost]`: attach to target creature you control; sorcery speed | M3 ★ |
| 702.7 | First Strike | Deals combat damage in the first-strike damage step | M4 ★ |
| 702.8 | Flash | May be cast any time you could cast an instant | M4 ★ |
| 702.9 | Flying | Can be blocked only by flying/reach creatures | M4 ★ |
| 702.10 | Haste | Ignores summoning sickness | M4 ★ |
| 702.11 | Hexproof | Can't be targeted by opponents' spells/abilities; "hexproof from" variants | M4 ★ |
| 702.12 | Indestructible | Not destroyed by lethal damage or destroy effects | M4 ★ |
| 702.13 | Intimidate | Blockable only by artifact creatures or creatures sharing a color | M5 |
| 702.14 | Landwalk | Unblockable while the defender controls the named land type | M5 |
| 702.15 | Lifelink | Damage dealt also causes its controller to gain that much life | M4 ★ |
| 702.16 | Protection | DEBT: can't be Damaged, Enchanted/Equipped, Blocked, Targeted by the quality | M4 ★ |
| 702.17 | Reach | Can block flying creatures | M4 ★ |
| 702.18 | Shroud | Can't be the target of any spell or ability | M5 |
| 702.19 | Trample | Excess combat damage beyond lethal can go to the player/planeswalker/battle | M4 ★ |
| 702.20 | Vigilance | Doesn't tap to attack | M4 ★ |
| 702.21 | Ward | When targeted by an opponent, counter unless they pay the cost | M4 ★ |
| 702.22 | Banding | Combat bands; the defender's damage-assignment control flips | M5 |
| 702.23 | Rampage | +N/+N per blocker beyond the first | M5 |
| 702.24 | Cumulative Upkeep | Age counter each upkeep; pay the cost per counter or sacrifice | M5 |
| 702.25 | Flanking | Blockers without flanking get -1/-1 | M5 |
| 702.26 | Phasing | Phases in/out on the untap step; treated as nonexistent while phased out | M5 |
| 702.27 | Buyback | Optional additional cost; on resolution return to hand | M5 |
| 702.28 | Shadow | Blocks/blocked only by shadow creatures | M5 |
| 702.29 | Cycling | `[Cost]`, discard: draw a card; typecycling variants | M4 ★ |
| 702.30 | Echo | Pay the echo cost on your next upkeep or sacrifice | M5 |
| 702.31 | Horsemanship | Like flying, horsemanship only | M5 |
| 702.32 | Fading | Fade counters; remove one each upkeep or sacrifice | M5 |
| 702.33 | Kicker | Optional additional cost; "if kicked" (multikicker) | M4 ★ |
| 702.34 | Flashback | Cast from the graveyard for the flashback cost, then exile | M4 ★ |
| 702.35 | Madness | Discard into exile, then may cast for the madness cost | M5 |
| 702.36 | Fear | Blockable only by black or artifact creatures | M5 |
| 702.37 | Morph | Cast face down as a 2/2 for {3}; turn up for the morph cost (megamorph) | M5 |
| 702.38 | Amplify | Reveal cards sharing a creature type to enter with counters | M5 |
| 702.39 | Provoke | On attack, untap target creature and force it to block | M5 |
| 702.40 | Storm | Copy for each spell cast before it this turn | M5 |
| 702.41 | Affinity | Costs {1} less per [quality] you control | M5 |
| 702.42 | Entwine | Pay extra to choose all modes | M5 |
| 702.43 | Modular | Enter with N +1/+1 counters; on death move them to an artifact creature | M5 |
| 702.44 | Sunburst | Counters equal to the number of colors of mana spent | M5 |
| 702.45 | Bushido | +N/+N when blocking or blocked | M5 |
| 702.46 | Soulshift | On death return a Spirit with mana value ≤ N | M5 |
| 702.47 | Splice | Reveal from hand to add its text onto an Arcane spell | M5 |
| 702.48 | Offering | Sacrifice a [type] to cast at flash speed with a reduced cost | M5 |
| 702.49 | Ninjutsu | Return an unblocked attacker to swap in from hand, tapped and attacking | M5 |
| 702.50 | Epic | Can't cast spells for the rest of the game; copy each upkeep | M5 |
| 702.51 | Convoke | Tap creatures to help pay | M4 ★ |
| 702.52 | Dredge | Replace a draw with milling N to return this card | M5 |
| 702.53 | Transmute | Discard: tutor a card with the same mana value; sorcery speed | M5 |
| 702.54 | Bloodthirst | Enter with counters if an opponent was dealt damage this turn | M5 |
| 702.55 | Haunt | On death, exile haunting a creature; trigger again when that creature dies | M5 |
| 702.56 | Replicate | Pay any number of times; copy that many times | M5 |
| 702.57 | Forecast | Reveal from hand during upkeep to activate | M5 |
| 702.58 | Graft | Enter with counters; move one to another creature as it enters | M5 |
| 702.59 | Recover | When a creature goes to your graveyard, pay or exile | M5 |
| 702.60 | Ripple | Reveal the top N; cast same-name cards free | M5 |
| 702.61 | Split Second | While on the stack, players can't cast spells or activate non-mana abilities | M5 |
| 702.62 | Suspend | Exile with time counters; remove one each upkeep; cast free (with haste) | M5 |
| 702.63 | Vanishing | Time counters; remove one each upkeep; sacrifice at the last | M5 |
| 702.64 | Absorb | Prevent N of each damage to it | M5 |
| 702.65 | Aura Swap | Exchange with an Aura card in hand | M5 |
| 702.66 | Delve | Exile graveyard cards to pay generic mana | M5 |
| 702.67 | Fortify | Attach a Fortification to a land | M5 |
| 702.68 | Frenzy | +N/+0 if it attacks and isn't blocked | M5 |
| 702.69 | Gravestorm | Copy for each permanent put into a graveyard this turn | M5 |
| 702.70 | Poisonous | Combat damage to a player → N poison counters | M5 |
| 702.71 | Transfigure | Sacrifice: tutor a creature with the same mana value | M5 |
| 702.72 | Champion | Exile another [object] on ETB or sacrifice; return it when this leaves | M5 |
| 702.73 | Changeling | CDA: every creature type | M4 |
| 702.74 | Evoke | Alternative cost; sacrifice on ETB | M5 |
| 702.75 | Hideaway | Exile one of the top N face down; play it later | M5 |
| 702.76 | Prowl | Alternative cost if a Rogue dealt combat damage this turn | M5 |
| 702.77 | Reinforce | Discard: N +1/+1 counters on a target creature | M5 |
| 702.78 | Conspire | Tap two creatures sharing a color to copy | M5 |
| 702.79 | Persist | Return with a -1/-1 counter if it had none | M5 |
| 702.80 | Wither | Damage to creatures is dealt as -1/-1 counters | M5 |
| 702.81 | Retrace | Cast from the graveyard by discarding a land | M5 |
| 702.82 | Devour | Sacrifice creatures as it enters for N counters each | M5 |
| 702.83 | Exalted | +1/+1 to a creature attacking alone | M5 |
| 702.84 | Unearth | Return from the graveyard with haste; exile at end of turn or when it would leave | M5 |
| 702.85 | Cascade | Exile until a cheaper nonland card; cast it free | M5 |
| 702.86 | Annihilator | On attack, the defending player sacrifices N permanents | M5 |
| 702.87 | Level Up | Sorcery-speed level counters (leveler cards, 711) | M5 |
| 702.88 | Rebound | Exile on resolution if cast from hand; cast free next upkeep | M5 |
| 702.89 | Umbra Armor | If the enchanted permanent would be destroyed, remove damage and destroy the Aura instead | M5 |
| 702.90 | Infect | Damage to players as poison, to creatures as -1/-1 counters | M5 |
| 702.91 | Battle Cry | Other attackers get +1/+0 | M5 |
| 702.92 | Living Weapon | Create a 0/0 Germ and attach to it | M5 |
| 702.93 | Undying | Return with a +1/+1 counter if it had none | M5 |
| 702.94 | Miracle | Cast for the miracle cost when drawn as the first card this turn | M5 |
| 702.95 | Soulbond | Pair with another creature for a shared bonus | M5 |
| 702.96 | Overload | Alternative cost: "target" becomes "each" | M5 |
| 702.97 | Scavenge | Exile from the graveyard: counters equal to its power | M5 |
| 702.98 | Unleash | May enter with a +1/+1 counter; can't block while it has one | M5 |
| 702.99 | Cipher | Encode onto a creature; recast a copy on its combat damage | M5 |
| 702.100 | Evolve | +1/+1 counter when a bigger creature enters under your control | M5 |
| 702.101 | Extort | On cast, may pay {W/B} to drain 1 | M5 |
| 702.102 | Fuse | Cast both halves of a split card from hand | M5 |
| 702.103 | Bestow | Cast as an Aura; becomes a creature when unattached | M5 |
| 702.104 | Tribute | An opponent chooses counters or the "if tribute wasn't paid" effect | M5 |
| 702.105 | Dethrone | +1/+1 counter attacking the player with the most life (works in two-player) | M5 |
| 702.106 | Hidden Agenda | Conspiracy only | OOS |
| 702.107 | Outlast | `[Cost]`, {T}: +1/+1 counter; sorcery speed | M5 |
| 702.108 | Prowess | +1/+1 until end of turn when you cast a noncreature spell | M4 ★ |
| 702.109 | Dash | Alternative cost; haste; return to hand at end of turn | M5 |
| 702.110 | Exploit | May sacrifice a creature on ETB | M5 |
| 702.111 | Menace | Can't be blocked except by two or more creatures | M4 ★ |
| 702.112 | Renown | First combat damage to a player → counters and renowned | M5 |
| 702.113 | Awaken | Alternative cost: also make a land a 0/0 creature with counters | M5 |
| 702.114 | Devoid | CDA: colorless | M5 |
| 702.115 | Ingest | Combat damage → the player exiles their top card | M5 |
| 702.116 | Myriad | Token copies attacking each other opponent (no effect in two-player; parse-only) | OOS |
| 702.117 | Surge | Alternative cost if you or a teammate cast another spell this turn | M5 |
| 702.118 | Skulk | Can't be blocked by creatures with greater power | M5 |
| 702.119 | Emerge | Alternative cost: sacrifice a creature, reduced by its mana value | M5 |
| 702.120 | Escalate | Additional cost per extra mode | M5 |
| 702.121 | Melee | +1/+1 per opponent attacked this combat | M5 |
| 702.122 | Crew | Tap creatures with total power N: Vehicle becomes an artifact creature | M4 ★ |
| 702.123 | Fabricate | N +1/+1 counters or N Servo tokens | M5 |
| 702.124 | Partner | Commander deck construction | OOS |
| 702.125 | Undaunted | Costs {1} less per opponent | M5 |
| 702.126 | Improvise | Tap artifacts to pay generic mana | M5 |
| 702.127 | Aftermath | Cast the second half only from the graveyard | M5 |
| 702.128 | Embalm | Exile from the graveyard: white Zombie token copy | M5 |
| 702.129 | Eternalize | Exile from the graveyard: 4/4 black Zombie token copy | M5 |
| 702.130 | Afflict | When blocked, the defending player loses N life | M5 |
| 702.131 | Ascend | City's blessing at ten permanents | M5 |
| 702.132 | Assist | Another player may help pay generic costs (works in two-player) | M5 |
| 702.133 | Jump-Start | Cast from the graveyard by also discarding a card, then exile | M5 |
| 702.134 | Mentor | On attack, +1/+1 counter on an attacking creature with lesser power | M5 |
| 702.135 | Afterlife | On death, N 1/1 flying Spirit tokens | M5 |
| 702.136 | Riot | Choose a +1/+1 counter or haste | M5 |
| 702.137 | Spectacle | Alternative cost if an opponent lost life this turn | M5 |
| 702.138 | Escape | Cast from the graveyard by exiling other cards | M5 |
| 702.139 | Companion | Outside-the-game deckbuilding condition; {3} special action | M5 |
| 702.140 | Mutate | Merge onto a non-Human creature (730) | M5 |
| 702.141 | Encore | Exile from the graveyard: token copies attack each opponent | M5 |
| 702.142 | Boast | Activate only if it attacked this turn, once per turn | M5 |
| 702.143 | Foretell | Exile face down for {2}; cast later for the foretell cost | M5 |
| 702.144 | Demonstrate | On cast, may copy; then an opponent copies too | M5 |
| 702.145 | Daybound and Nightbound | DFC faces tied to day/night (731) | M5 |
| 702.146 | Disturb | Cast transformed from the graveyard | M5 |
| 702.147 | Decayed | Can't block; sacrifice at end of combat after attacking | M5 |
| 702.148 | Cleave | Alternative cost removes bracketed text | M5 |
| 702.149 | Training | +1/+1 counter when attacking with a creature of greater power | M5 |
| 702.150 | Compleated | Pay life for Phyrexian mana → fewer loyalty counters | M5 |
| 702.151 | Reconfigure | Attach/unattach as Equipment; not a creature while attached | M5 |
| 702.152 | Blitz | Alternative cost; haste, "draw on death"; sacrifice at end of turn | M5 |
| 702.153 | Casualty | Sacrifice a creature with power ≥ N to copy | M5 |
| 702.154 | Enlist | Tap a non-attacking creature to add its power | M5 |
| 702.155 | Read Ahead | Choose the starting Saga chapter | M5 |
| 702.156 | Ravenous | Enter with X counters; draw if X ≥ 5 | M5 |
| 702.157 | Squad | Pay additional costs to create token copies | M5 |
| 702.158 | Space Sculptor | Sector designations (Space Beleren, Un-set) | OOS |
| 702.159 | Visit | Attraction only | OOS |
| 702.160 | Prototype | Alternative smaller P/T and mana cost (718) | M5 |
| 702.161 | Living Metal | An artifact creature during your turn | M5 |
| 702.162 | More Than Meets the Eye | Cast converted (Transformers) | M5 |
| 702.163 | For Mirrodin! | Create a 2/2 Rebel and attach to it | M5 |
| 702.164 | Toxic | Combat damage to a player also gives N poison counters | M5 |
| 702.165 | Backup | ETB +1/+1 counters on a target; grants its abilities if another creature | M5 |
| 702.166 | Bargain | Optional sacrifice of an artifact/enchantment/token as an additional cost | M5 |
| 702.167 | Craft | Exile with materials: return transformed | M5 |
| 702.168 | Disguise | Face-down 2/2 with ward {2}; turn up for the disguise cost | M5 |
| 702.169 | Solved | Case abilities once solved (719) | M5 |
| 702.170 | Plot | Exile from hand (special action); cast free on a later turn at sorcery speed | M5 |
| 702.171 | Saddle | Tap creatures with total power N: becomes saddled; sorcery speed | M5 |
| 702.172 | Spree | Choose one or more modes, paying each mode's additional cost | M5 |
| 702.173 | Freerunning | Alternative cost if an Assassin/commander dealt combat damage | M5 |
| 702.174 | Gift | Optional "gift" to an opponent that enables a bonus | M5 |
| 702.175 | Offspring | Additional cost → 1/1 token copy on ETB | M5 |
| 702.176 | Impending | Alternative cost: enters with time counters, not a creature until they're gone | M5 |
| 702.177 | Exhaust | Activated ability: activate only once | M5 |
| 702.178 | Max Speed | Grants an ability while your speed is 4 | M5 |
| 702.179 | Start Your Engines! | Player speed 1–4; increases once per turn when opponents lose life on your turn | M5 |
| 702.180 | Harmonize | Cast from the graveyard, tapping a creature to reduce the cost | M5 |
| 702.181 | Mobilize | On attack, N 1/1 Warrior tokens tapped and attacking; sacrificed at end step | M5 |
| 702.182 | Job Select | Equipment ETB: 1/1 Hero token and attach | M5 |
| 702.183 | Tiered | Choose one mode and pay its additional cost | M5 |
| 702.184 | Station | Tap another creature: charge counters equal to its power; sorcery speed (721) | M5 |
| 702.185 | Warp | Cast from hand for the warp cost; exiled at the next end step and may be cast later | M5 |
| 702.186 | ∞ (Infinity) | Grants an ability while the permanent is harnessed | M5 |
| 702.187 | Mayhem | Cast from the graveyard for the mayhem cost if discarded this turn | M5 |
| 702.188 | Web-slinging | Alternative cost: pay and return a tapped creature you control | M5 |
| 702.189 | Firebending | On attack add N {R} that lasts until end of combat | M5 |
| 702.190 | Sneak | During the declare blockers step, alternative cost returning an unblocked creature | M5 |
| 702.191 | Increment | +1/+1 counter when you cast a spell with more mana spent than its power or toughness | M5 |
| 702.192 | Paradigm | After the first resolution, a copy in exile each precombat main phase that you may cast | M5 |
| 702.193 | Power-up | Activate once; cost reduced by its mana cost if it entered this turn | M5 |
| 702.194 | Teamwork | Optional additional cost: tap creatures with total power ≥ N | M5 |
| 702.195 | Storied | Enduring story once you control three or more artifacts/Sagas/legendaries | M5 |
| *(702.196)* | *Beam me up* | *2026-11-06 CR only: graveyard-cast alternative cost involving returning a creature to hand* | *M5 (not in pinned CR)* |

### Other priority mechanics (not keywords)

Mechanics that are ★ priority but don't have a 701/702 number: mana abilities
(605), priority
(117), costs including X (107.3, 118), modal spells (700.2), +1/+1 counters
(122.1a), predefined tokens such as Treasure, Clue and Food (111.10), the
legend rule (704.5j), Auras (303.4), Equipment (301.5), planeswalker loyalty
(306/606), Sagas (714), DFCs/MDFCs (712), copy effects (707), layers (613),
replacement/prevention (614–616), "dies" and leaves-the-battlefield triggers
(603.6/603.10), and summoning sickness (302.6).

### Costs, payment and targets: where they are implemented

- 107.4e / 202.2d / 202.3f hybrid mana: `Mana::Cost#hybrid`; 601.2h payment `Engine::Payment`.
- 733.1 / 605.3 rewinding a cast: offered until an irreversible mana ability is activated.
- 601.2b-d kicker, additional costs, mode counts, optional and distinct targets, dividing: `Engine::CastChoices`.
- 601.2h / 602.2b chosen costs (sacrifice, tap N, remove counters, graveyard costs): `Mechanics::Costs`.
- 602.5b activation limits; 118.12 / 701.6a paying while resolving and countering abilities; 702.21 ward.

---

## Out of scope (listed for completeness)

- **Section 8, Multiplayer Rules (800–811)**: range of influence, attack multiple players, Two-Headed Giant, Emperor, and the other team variants.
- **Section 9, Casual Variants (900–905)**: Planechase, Vanguard, Commander, Archenemy, Conspiracy Draft.
- Variant-only card types (311–315), ante (407), stickers (123), Attractions (717, 701.51–52, 702.159), Contraptions (701.45), Space Sculptor (702.158, 704.5u), and the variant SBAs and turn-based actions (704.6, 703.4e, 703.4h).
- Mechanics that are legal in two-player games but rare (goad, vote, monarch, initiative, companion, dethrone) are kept as **M5**, not OOS.

## Verification notes

- Every 701/702 number and name comes from the pinned TXT heading lines. Descriptions paraphrase each rule's "a" subrule, which was read for all entries.
- 704.5 letters a–aa, 116.2 a–m, 613.1/613.4/613.7, 616.1a–f, 601.2a–i, 605.1a, 703.4a–q and 733.1 were read in full or near-full.
- Descriptions of the section 1–6 rules marked n/a or M1 are paraphrases. Check the rule text before implementing; this document is a checklist, not a substitute.
- Not verified: subrule-level wording changes between 2026-09-25 and 2026-11-06, and the exact date of the mana-ability (605.1a) change. It is present in the 2026-09-25 text, and this document doesn't claim when it was introduced.
