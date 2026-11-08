# Plan: Star Trek (`trk`) fully verified

Goal: every card of the Star Trek expansion (Scryfall set `trk`, released
2026-11-13, 311 unique cards) is converted to Enjine card data, passes
validation, and is verified in play. Then the README lists `trk` as a
**verified set**.

Status (2026-11-09): 227 of 311 cards convert (`lib/enjine/sets/trk.json`); 84 are listed as
unsupported with the capabilities they still need. Cards waiting on a capability are named
in each group's section below.

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
- Done: "dilemmas faced this turn" is the amount `{"dilemmas_this_turn": "you"}`
  (`PlayerState#turn_log`, see `Engine::TurnHistory`).
- Assimilate's linked "exiled with" ability (701.72c, 607) for Borg Cube.
- Done: strange new worlds cost reductions (`cost_reduction` with a `distinct_names`
  amount), `pump` with computed amounts, and characteristic-defining P/T (card data
  `"power": <amount>`, layer 7a).
- Done: `RulesMonitor` adds static-ability pumps (fixed, computed, conditional) in its
  independent P/T check, so the converter's static-line pattern matches
  "Artifact creatures you control get +1/+1" case-insensitively.

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

## Costs, mana and targets

Rule numbers from the pinned 2026-09-25 CR (`cr0925`).

| Capability | Rules | Card data | Status |
| --- | --- | --- | --- |
| Hybrid mana `{R/G}` | 107.4e, 202.2d, 202.3f, 601.2h | mana costs; each symbol paid by either color | done (monocolored hybrid `{2/B}` and Phyrexian: todo) |
| Cancelling a cast | 733.1, 605.3 | — | "cancel" only until something irreversible is paid (a Treasure's sacrifice); from then on only payments that keep the rest payable are offered |
| Chosen costs | 601.2h, 602.2b, 701.21a | costs `sacrifice_permanent`, `tap_permanents`, `remove_counters` (paid entries in `GameObject#paid`, condition `sacrificed`) | done |
| Graveyard costs | 113.6m | costs `exile_self_from_graveyard`, `bottom_self_from_graveyard` | done |
| Kicker / additional costs | 702.33a/d/g, 601.2b, 601.2f | abilities `kicker`, `additional_cost`; condition `kicked`; spell `kicked_targets` | done |
| Activation restrictions | 602.5b, 602.5d | `limit: "once_each_turn"`, `only_if`, `timing: "your_turn"` | done |
| Target variants | 601.2c, 601.2d, 115.1d | target `{"filter", "optional", "distinct_from"}`; spell `divide` + effect `distribute_counters` | done |
| Mode counts | 700.2 | `choose: {"min", "max"}`, `choose_if`, `unchosen` | done |
| Paying while resolving | 118.12, 118.12a, 701.6a | effects `pay`, `counter_unless_pays`; a `pay` frame | done |
| Countering abilities / can't be countered | 701.6a, 101.2 | filter `stack_ability`; keyword `cant_be_countered` | done |
| Ward | 702.21a | ability `ward` | done |
| Choice among listed colors | 106.4, 608.2d | `add_mana` `colors` | done |

Converted with these: Armus, Skin of Evil; Astute Terraformer; Captain James T. Kirk; Cetacean Ops; Cleveland
Booker, Empath; Collation Trimatrix; Consider the Prime Directive; Constable Odo; D'Vana Tendi, Optimistic
Ensign; Dal R'El, Augment Orphan; DOT-7 Repair Squad; Eject the Warp Core; General Chang, Cold Warrior; Ghost of
Illyria; Gowron, Eager for Battle; Highly Illogical; Humpback Whales; L'Rell, Fierce Visionary; Lieutenant
Commander Data; Lore, Positronic Provocateur; Lt. Cmdr. Geordi La Forge; Organic Avulsion Unit; Photosynthetic
Physician; Relentless Drednok; Subcommander T'Pol; Suus Mahna Practitioner; The Doctor, EMH; The Duras Sisters;
U.S.S. Enterprise-A, Free Spirit; Wesley Crusher, Starfleet Cadet (and tmt: Foot Elite, Mechanized Ninja Cavalry).
Token colors aren't modeled yet (no color characteristic), as for the earlier Officer tokens.

Still waiting on other capabilities: Marooned (can't be beamed up, "doesn't untap"), Pure Energy (beam me up),
Worf, Honor-Bound Warrior (power doubling, total power), Engineered Explosives (mana value equal to an amount; the
sacrificed source's counters are kept in the ability's memory `source_counters`), Starfleet Academy (creature-type
count; a mana ability with a variable amount and color choice), Commander Raffi Musiker, Daniels, Temporal Agent
and Emergency Holographic Crew (exiling or returning cards from a graveyard).

Amounts, conditions, turn history, statics and layers (translations): Academy Instructor,
Anthropological Mission, Cantankerous Captain, Captain Jonathan Archer, Captain Michael
Burnham, Cloak and Phaser, Collective Drone, Conquest Mission, De-evolve, Genesis Effect,
Gul Dukat, Hologram Janeway, I'm a Doctor, Impossible Choice, Jadzia Dax, Jake Sisko,
La'An Noonien-Singh, Locutus, Make It So, Pah-Wraith, Picard, Planetary Bombardment,
Resistance Is Futile, Rok-Tahk, Romulan Bird-of-Prey, Saavik, Sarcophagus, Sarek,
Sickbay, Starfleet Spanner Jockey, Tactical Officer, Tal Shiar Operative, Test of
Identity, The Destruction of Praxis, The Traveler, Una Chin-Riley, Vengeance Mission.
Waiting on other capabilities: Miles O'Brien ("up to one" target), Seven of Nine
(activation restriction; the 7b setting effect is done), Grand Nagus Zek (once-each-turn
trigger), Shuttle Ace and Hemmer ("becomes tapped" trigger), Targ Wrangler (choose and
sacrifice), Antagonist Incorporator and Hive Mind Coprocessor (a cost paid inside "may";
granting the triggered ability is done).

Trigger capabilities (group 4: becomes tapped, counters put, becomes the target, leaves a
graveyard, activates an ability, cast filters and chosen values, once each turn, additional
triggers, created and reflexive triggers, `may` decided by another player, as-enters number and
card-name choices, enters tapped unless, enters untapped triggers, another counter of a kind).
Converted by translation: A Good Day to Die, Battle-Scarred Survivalist, Dathon, David and Carol
Marcus, Dr. Beverly Crusher, Federation Outpost, Kai Winn, Khan, MACO Strike Team (token colors wait for G3), Ni'Var Science Academy, Nyota
Uhura, Planetary Patrol, Q Continuum, Quark's Bar, Ravenous Cosmozoan, Starfleet Security, Tell
Me What You See, U.S.S. Reliant, Vash. Their trigger primitives are in place but they still wait
for other groups: Captain Jean-Luc Picard, Sulu, Jett Reno, Gabriel Lorca, Sela, Beckett Mariner,
Hologram Stalker, Support Mission, The Unicomplex, Dahar Master, The Naked Time,
Dr. Leonard "Bones" McCoy, Sylvia Tilly, The Inner Light.

## Replacement, prevention and player rules (group 5)

| Capability | Card data | Rules | Status |
| --- | --- | --- | --- |
| Draw replacement ("draw two instead") | ability `draw_replacement` | 614.11, 614.5 | done (one per draw; another applies to each draw it makes) |
| Destruction replacement (remove counters / damage instead) | ability `destroy_replacement` | 614.1a, 614.8, 704.5g-h | done (effects, lethal damage, deathtouch; not sacrifice or 0 toughness) |
| Token replacement ("that many X tokens instead") | ability `token_replacement` | 614.1a, 614.16, 111.1 | done |
| Lands enter untapped | ability `enters_untapped` | 614.12, 616.1 | done (applied after every "enters tapped") |
| Enters tapped and attacking | ability `enters_attacking` | 614.1c, 508.4 | done (attacks the defending player; choosing a planeswalker isn't offered yet) |
| "+1 of each kind" counters until end of turn | effect `counter_bonus` | 614.1a, 616.1 | done (applied before doubling) |
| "If it would die this turn, exile it instead" | effect `exile_if_dies` | 614.1a, 700.4 | done |
| Exile this spell as it resolves | effect `exile_this_spell` | 608.2n | done |
| Player hexproof, prevent all damage to a player, no maximum hand size, can't attack | effect `player_rule` (end_of_turn / until_your_next_turn) | 702.11c, 615.1, 402.2, 508.1c | done |
| Don't lose for 0 life, can't sacrifice [filter] | ability `player_rule` | 704.5a, 701.21a, 614.17b | done (`Engine#can_sacrifice?` guards sacrifice costs and effects) |
| Win / lose the game | effects `win_game`, `lose_game` | 104.2b, 104.3e | done (the rest of the resolving list stops) |
| Extra turns, "haven't begun an extra turn" | effect `extra_turn`, condition `began_extra_turn` | 500.7 | done (`state.extra_turns`: queue + players who began one) |
| Gain control (indefinite, until end of turn, by another player) | effect `gain_control` | 613.1b, 108.4, 506.4 | done (control returns in cleanup unless a newer change happened) |
| Add creature subtypes until end of turn | effect `add_subtypes` | 613.1d, 205.1b | done |
| Can't attack alone; can't be blocked by [filter]; can't be targeted by abilities from [sources] | keyword `cant_attack_alone`; abilities `cant_be_blocked_by`, `cant_be_targeted_by` | 506.5, 508.1c, 509.1b, 115.4 | done |
| Fight, bite, remove counters / all counters / damage | effects `fight`, `bite`, `remove_counters`, `remove_all_counters`, `remove_damage` | 701.14, 122.8, 120.6 | done |

CR 616.1 lets the affected player order several applicable replacement effects. Every pair
implemented so far has an order that player always prefers (stay on the battlefield before being
exiled, "+1" before doubling, untapped after tapped), so the engine applies that order without
asking; a decision frame is needed once two effects can be usefully ordered either way.

Converted: Mr. Spock, Pet Sehlat, Cold-Blooded Crew, Species 8472, Holo-Engineer, Deep Space Scan,
Georgiou (Officer tokens without color, like other token translations), Quark, Dr. McCoy, H.M.S.
Bounty, Warp Speed, Dr. Joseph M'Benga, Saru, Saurian Explorer, Stable Wormhole, Phlox, Tea, Earl
Grey, Hot, Warp Core.

Waiting on other capabilities: Brad Boimler ("becomes tapped" trigger), The Needs of the Many
(additional sacrifice cost), Peace in Our Time ("that player may", peace counter count), Kobayashi Maru
Scenario (modes not chosen before, up to one target), Khaaaaaaaaaaaannn! (twice X), Kira Nerys (the
entering creature as the trigger's object), Live Long and Prosper (can't be countered),
Rules of Acquisition (the target's controller, "if they do"), Worf (one target per opponent,
up to one), The Wrath of Khan (next-combat delayed trigger, exile from hand, edict), Amok Time (up to
one target, return from graveyard), Common Goal (one or two targets).

### Zone effects: library, hand, graveyard, edicts, linked exile

Primitives (2026-09-25 numbering unless noted): `dig` (look at or reveal the top N, take
cards matching a card spec, the rest to the bottom in a random order via the game RNG, in a
chosen order, or into the graveyard; 701.20a/e, 401.4), `reveal_until` (701.20a), `exile_top`
(its results are the exiled cards, for later effects and impulse permissions), `explore`
(701.44a), `choose_cards` (choose from an earlier effect's results, a hand or a graveyard, with
`then`/`otherwise` for "if you do"/"if you can't"), `sacrifice_choice` (edicts, in APNAP order,
101.4), `put_in_library` (top, bottom, or the owner's choice), `shuffle_into_library`
(701.24c), `shuffle_library`, `look_at_hand` (event `looked_at`, shown only to the looker and the
owner). `exile` and `return_to_hand` also move cards in graveyards (and hands/exile); `exile`
takes `link` (cards "exiled with" the source, 607.2a, kept in the source's memory) and
`until_source_leaves` (610.3). Selectors `"exiled_with"` and `{"controller_of": selector}` (last
known controller of what a resolving effect moved), condition `{"share_card_type": selector}`.
Card specs gained `not_types`, `permanent` and `mana_value`. `search_library` gained `searcher`,
`may`, a computed `count` ("up to that many") and `counters`.

Converted with these: 70,000 Light-Years from Home, All Good Things..., Automated Warfare
System, Branching Timeline, Cybernetic Specialist, D'Ghor Bloodletter, Dathon and Picard at
El-Adrel, Dominion Assault Force, Genesis Device, Guidance Failure, Hit It!, In the Pale
Moonlight, Salt Vampire, Spock, Always Your Friend, Temporal Conqueror, Test of Courage, Test of
Loyalty, U.S.S. Voyager, Will Riker, Temporal Anomaly, Artificial/Gaseous/Spatial/Subspace
Anomaly, Unexplored Territory (translations). Waiting on other capabilities: The Measure of a
Man, Those Old Scientists, Stray from History, Borg Cube ("up to N" / "one or two" targets);
Malfunctioning Holodeck (ward); Rutherford (cast trigger for a subtype), Erica Ortegas
(becomes tapped), Captain Kathryn Janeway ("that creature" trigger selector; an additional land
play static); Hoshi Sato (creature types among creatures), First Contact (first spell this
game), Deep Space 9 (the rules monitor's static pumps); V'Ger ("until your next turn");
There's Coffee in that Nebula, Pattern Buffer Preservation (beam me up).

`RulesMonitor#keyword?` now counts keywords granted by static abilities (haste from Hit It!,
flying or reach), so trk games with those grants no longer report false 302.6 / 702.9b findings.

## Pipeline

`script/convert_set` (to be written, run from the repo with network access):
1. Fetch the set from a card source (today the Scryfall API, `/cards/search?q=e:trk&unique=cards`; the converter keeps the source behind an adapter).
2. Map each card to Enjine data. Mechanical fields are mapped automatically, and
   abilities from a hand-maintained translation file:
   `data/translations/trk.json`, keyed by card name (names are unique across Magic).
3. Validate with `CardDefinition.from_h`, and write `lib/enjine/sets/trk.json`
   with `cards` (valid) and `unsupported` (name plus the missing capabilities).
4. The run prints the remaining count; the target is 0 unsupported.
