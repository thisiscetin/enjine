# DSL gaps: mechanics missing for FAIL and PARTIAL cards

Snapshot of 2026-11-11, taken from deckfinder through its MCP connection (`dsl_status scope: all`).
Of 1,025 cards in scope (the user's collection, decks and imported opponent decklists), 192 are
DSL FAIL (no script possible yet) and 87 are DSL PARTIAL (a best-effort script that leaves something out).
The reasons come from deckfinder's `db/card_scripts/**`, written against enjine 0.1.0.

Clusters are grouped by hand from each card's reason. A card can appear in more than one cluster.
Card names are real cards and appear here only to point at the gap; per
[the Standard program](standard.md), each mechanic is implemented and tested with **invented** cards.

## Quick wins (high impact, small effort)

Effort comes from a skim of `lib/` on 2026-11-11 (S: extend an existing primitive; M: a new decision or
rules plumbing). "Unblocks" counts live cards whose reason names only this gap; check each card's
full text when writing it.

| # | Change | Effort | Unblocks | Cards | Status |
|---|---|---|---|---|---|
| 1 | New amounts in `Mechanics::Amount` (`values.rb`, same pattern as `distinct_colors`): `library_size`, `card_types` (distinct card types among cards; kindred and battle nameable in filters), `greatest_mana_value` | S | 9 | Tarmogoyf, Fear of Missing Out, Keen-Eyed Curator, Kitsune's Technique; PARTIAL to exact: Patchwork Beastie, Violent Urge, Wildfire Wickerfolk, Singularity Rupture, Ill-Timed Explosion | Done (Unreleased): `card_types`, `greatest_mana_value`, `library_size` |
| 2 | Last-known `mana_value` and power for destroyed or sacrificed permanents: add `mana_value` to `TurnHistory#last_known_memory` and read LKI through `{result}` / sacrificed objects | S-M | 5 | Feed the Swarm, Seedship Impact, Tainted Treats, Bolg of the North, Rhovanion Rampager, Repurposing Bay | Done (Unreleased): LKI mana value/power for destroyed targets and `{result}` of sacrifices; `{"sacrificed": ...}` for costs. Bolg stays blocked: a reflexive trigger ("when you do") doesn't carry the last known information of what its parent moved |
| 3 | `discard` with `chooser: you` (reveal, then the caster picks the card, with a filter) | M | 6 | Duress, Deceit, Down Down to Goblin-town, Solve for Disappointment; PARTIAL to exact: Oildeep Gearhulk, Thought-Stalker Warlock | Done (Unreleased): `choose_cards` `put: discard` (with `from: {"hand": …}`, `reveal: "all"`) |
| 4 | `search_library` `put: graveyard` and `put: library_top` (after the shuffle) | S | 4 | Carnivorous Cultivator // Enroot, Loyal Tutor, Old Thrush; PARTIAL to exact: Insatiable Avarice | Done (Unreleased): `put: graveyard`, `put: library_top`; computed `for` bounds now work |
| 5 | `limit: once_each_turn` on `mana_ability` (reuse `LIMITS` from `stack_abilities.rb`) | S | 2 | Abzan Devotee, Barrels of Blasting Jelly | Done (Unreleased): `mana` `limit: "once_each_turn"` |
| 6 | `cost_modifier` `spells` filter by subtype and color | S | 2 | Dragonlord's Servant, The Fire Crystal | Done (Unreleased): `spells` takes `subtypes` and `colors` |
| 7 | `until_your_next_turn` duration on `become` and keyword grants (already on `pump`, player rules, damage replacements) | S | 2 | Elspeth, Storm Slayer; PARTIAL to exact: Hydro-Man | Done (Unreleased): `grant` and `become` `duration: "until_your_next_turn"` |
| 8 | Exile-this-permanent cost | S | 2 | Sapling Nursery; PARTIAL to exact: The Echoverse Fulcrum | Done (Unreleased): cost `"exile_self"` |
| 9 | `additional_triggers` with an `of` filter for any cause (CAUSES is only `you_gain_life`) | S | 1-3 | Katara; partly Roaming Throne, Wizard's Staff | Done (Unreleased): `of` filter (with `other`, `"subtypes": "chosen"`); `cause` optional |

Larger but high impact, next in line: **plot** (7 cards, M; done, Unreleased: ability and effect `plot`; Doc Aurlock's
"plotting costs {2} less" is still open), a **static that grants loyalty abilities** (about 5, M),
and the **play-permission** extensions (19 cards, but a mix of separate gaps, L).

## Ranking

| # | Missing mechanic | Cards | FAIL | PARTIAL |
|---|---|---|---|---|
| 1 | [Unimplemented keyword mechanics](#1) | 36 | 18 | 18 |
| 2 | [Cast/play permissions](#2) | 19 | 15 | 4 |
| 3 | [Cost modifiers](#3) | 15 | 12 | 3 |
| 4 | [Last-known information](#4) | 15 | 13 | 2 |
| 5 | [Zone-move destinations (search/dig/reveal/return)](#5) | 15 | 11 | 4 |
| 6 | [Mana](#6) | 14 | 10 | 4 |
| 7 | [Counters](#7) | 12 | 7 | 5 |
| 8 | [Costs & activation limits](#8) | 12 | 6 | 6 |
| 9 | [Set types / name (become, return as)](#9) | 11 | 8 | 3 |
| 10 | [Trigger gaps (extra triggers, Torpor, batched, other events)](#10) | 11 | 10 | 1 |
| 11 | [Selectors / static filters](#11) | 11 | 10 | 1 |
| 12 | [Replacement effects](#12) | 10 | 7 | 3 |
| 13 | [Loyalty abilities](#13) | 9 | 6 | 3 |
| 14 | [Conditions on an earlier effect's result](#14) | 9 | 7 | 2 |
| 15 | [Combat](#15) | 9 | 8 | 1 |
| 16 | [Chosen / filtered discard](#16) | 8 | 5 | 3 |
| 17 | [Card names](#17) | 8 | 6 | 2 |
| 18 | [Simultaneous moves](#18) | 8 | 5 | 3 |
| 19 | [Other-player / non-targeted choices](#19) | 7 | 7 | 0 |
| 20 | [Card-type counting (delirium, Goyf)](#20) | 7 | 4 | 3 |
| 21 | [Amounts (library size, greatest MV)](#21) | 7 | 4 | 3 |
| 22 | [Durations (until your next turn / next end step)](#22) | 6 | 4 | 2 |
| 23 | [Turn-history conditions](#23) | 5 | 5 | 0 |
| 24 | [Owner filters](#24) | 5 | 3 | 2 |
| 25 | [Copy exceptions](#25) | 5 | 4 | 1 |
| 26 | [Modal (per-turn, up to X, repeat)](#26) | 4 | 3 | 1 |
| 27 | [Forced retarget](#27) | 4 | 4 | 0 |
| 28 | [Outside the game](#28) | 3 | 3 | 0 |
| 29 | [Player rules](#29) | 2 | 1 | 1 |

Keyword breakdown: plot 7, craft 4, Case / suspect 3, leyline / opening hand 3, offspring 2, descend 2, impending 2, collect evidence 2, commit a crime 2, harness 2, ninjutsu / sneak 2, Room 1, manifest dread 1, bargain 1, split second 1, pawprint 1.

<a id="1"></a>
## 1. Unimplemented keyword mechanics (36)

**Needs:** Set keywords and keyword actions with no primitive.

| Card | State | Reason |
|---|---|---|
| Aven Interrupter | FAIL | plot (exile target spell, it becomes plotted) not supported |
| Braided Net // Braided Quipu | FAIL | Craft with artifact (exile this and another artifact / artifact card from graveyard, return transformed) is not supported; also 'its activated abilities can't be activated for as long as it remains tapped' and putting itself third from the top |
| Case of the Ransacked Lab | FAIL | Case enchantment (To solve / Solved) mechanic not supported |
| Case of the Stashed Skeleton | PARTIAL | Suspect and solving a Case aren't primitives. The token is created with menace and can't block, which is what suspecting it gives. 'You control no suspected Skeletons' is read as 'no Skeleton you control has can't-block', and being solved is a 'solved' counter put on the Case at the beginning of your end step. |
| Case of the Uneaten Feast | FAIL | Case mechanic (To solve / Solved, CR 719) not supported; also granting 'you may cast this card from your graveyard' to graveyard cards until end of turn |
| Clay-Fired Bricks // Cosmium Kiln | FAIL | Craft with artifact (exile this and another artifact / artifact card from graveyard, return transformed) is not supported |
| Corpses of the Lost | PARTIAL | The end-step trigger ('if you descended this turn, you may pay 1 life; if you do, return this to its owner's hand') is left out: no condition for descend (a permanent card put into your graveyard this turn). |
| Deadly Cover-Up | FAIL | Collect evidence (CR 701.59) not supported; also searching graveyard/hand/library for cards with that name |
| Doc Aurlock, Grizzled Genius | PARTIAL | 'Plotting cards from your hand costs {2} less' is left out: Enjine has no plot. |
| Dust Animus | PARTIAL | Plot {1}{W} is left out (no plot in Enjine). 'Enters with two +1/+1 counters and a lifelink counter if you control five or more untapped lands' is an ETB trigger that checks the same condition, because enters_with_counters takes no condition. |
| Forsaken Miner | PARTIAL | the 'Whenever you commit a crime, you may pay {B}. If you do, return this card from your graveyard to the battlefield' ability: Enjine has no commit-a-crime trigger |
| Iridescent Vinelasher | PARTIAL | Offspring {2} is modelled as kicker {2} plus 'when this enters, if it was kicked, create a 1/1 token copy of it' (Enjine has no offspring primitive; it counts as kicked for kicker-matters effects) |
| Kaito, Bane of Nightmares | FAIL | Ninjutsu (CR 702.49) not supported |
| Kellan Joins Up | PARTIAL | plot: the exiled card can't become plotted, so it is cast without paying its mana cost at the beginning of your next precombat main phase (a delayed trigger, you may decline) instead of on any later turn at sorcery speed |
| Leyline of Resonance | PARTIAL | the Leyline opening-hand clause (begin the game with it on the battlefield) has no primitive; it must be cast for {2}{R}{R} |
| Leyline of the Void | PARTIAL | the opening-hand clause, and the replacement covers only opponents' creatures dying (exile_if_dies) instead of every card going to an opponent's graveyard from anywhere |
| Magda, the Hoardmaster | FAIL | 'Whenever you commit a crime' trigger not supported |
| Molten Collapse | FAIL | Descend condition 'if you descended this turn' (no turn-history amount/condition for permanent cards put into your graveyard) |
| Ninja Teen | FAIL | Level 3: granting sneak {3}{B} to creature cards in your graveyard and casting them from the graveyard using sneak: no primitive grants sneak / alternative costs to graveyard cards |
| Outcaster Trailblazer | PARTIAL | Plot {2}{G} (no plot keyword) |
| Overlord of the Balemurk | FAIL | Impending (CR 702.176) not supported |
| Overlord of the Floodpits | PARTIAL | Impending 4—{1}{U}{U} (no impending: it can only be cast as the 5-mana creature) |
| Pillage the Bog | PARTIAL | Plot {1}{B}{G} (exile from hand, cast later without paying its mana cost): Enjine has no plot |
| Quicksilver, Brash Blur | PARTIAL | 'If Quicksilver is in your opening hand, you may begin the game with him on the battlefield': Enjine has no opening-hand (leyline) action |
| Samut, Tyrant of Naktamun | FAIL | split second (CR 702.61) has no keyword, and no ability grants it to instant and sorcery spells you control |
| Season of the Burrow | FAIL | pawprint modes ({P} budget of up to five, CR 700.2i) and choosing the same mode more than once: modal spells take only a min/max count of distinct modes |
| Slickshot Show-Off | FAIL | Plot (CR 702.170) not supported |
| Spring-Loaded Sawblades // Bladewheel Chariot | FAIL | Craft with artifact (exile this and another artifact / artifact card from graveyard, return transformed) is not supported (card appears twice in the input; listed once) |
| Starscape Cleric | FAIL | approximation: offspring written as kicker - rejected, exact only |
| The Enigma Jewel // Locus of Enlightenment | PARTIAL | Craft with four or more nonlands with activated abilities {8}{U} is left out (no craft), so it never transforms; the back face Locus of Enlightenment has none of its abilities (gaining the exiled cards' activated abilities, copying non-mana abilities) |
| The Mind Stone | FAIL | Harness / ∞ (Infinity Stone) abilities that become active once harnessed are not supported |
| The Soul Stone | PARTIAL | harness cost 'Exile a creature you control' is paid by sacrificing a creature instead (no exile-a-permanent cost); harnessing is modelled as the Stone gaining the ∞ upkeep trigger for as long as it stays on the battlefield, with the harness ability limited to once (re-harnessing does nothing on the real card) |
| Torch the Tower | FAIL | Bargain (CR 702.166) not a primitive; and 'if a permanent dealt damage by this spell would die this turn, exile it' needs a replacement conditional on the damage actually being dealt (exile_if_dies on the target ignores prevented damage) |
| Turn Inside Out | PARTIAL | 'When it dies this turn, manifest dread' is left out (no manifest / face-down 2/2 creatures) |
| Unholy Annex // Ritual Chamber | PARTIAL | Room layout isn't supported: written as the Unholy Annex half plus a once-only sorcery-speed {3}{B}{B} 'unlock' ability for Ritual Chamber; Ritual Chamber can't be cast on its own and the mana value is always 3 |
| Urgent Necropsy | PARTIAL | the additional cost 'collect evidence X, where X is the total mana value of the permanents this spell targets' (collect evidence has no primitive), so it is cheaper than printed |

<a id="2"></a>
## 2. Cast/play permissions (19)

**Needs:** `play_permission` from the graveyard, with a condition, while you control the source, for one card, with alternative costs (life, waterbend); free-cast and flash-granting statics; `until_your_next_end_step`.

| Card | State | Reason |
|---|---|---|
| Bard's Company | FAIL | 'You may cast this spell as though it had flash if you control a Human': no conditional flash / cast-timing permission |
| Case of the Uneaten Feast | FAIL | Case mechanic (To solve / Solved, CR 719) not supported; also granting 'you may cast this card from your graveyard' to graveyard cards until end of turn |
| Dracogenesis | FAIL | no standing permission 'You may cast Dragon spells without paying their mana costs' |
| Dragonhawk, Fate's Tempest | FAIL | 'until your next end step' play duration and a delayed amount 'each of those cards that are still exiled' not supported |
| Flashback | FAIL | Granting flashback to a graveyard card with a cost equal to that card's mana cost (flashback cost must be a fixed string) |
| Hama, the Bloodbender | FAIL | permission to cast the exiled card during your turn for as long as you control Hama by waterbending {X} (X = its mana value) instead of its mana cost: play_permission has no while-you-control duration, your-turn restriction or alternative waterbend cost |
| Haste Magic | PARTIAL | 'You may play it until your next end step' is modelled as until end of this turn (Enjine has no 'until your next end step' duration); differs only when cast on an opponent's turn |
| Inside Information | FAIL | play permission with an alternative cost 'pay life equal to its mana value rather than pay its mana cost' (play_permission has no life-for-mana-cost alternative) |
| Inti, Seneschal of the Sun | FAIL | Play permission 'until your next end step' (only end_of_turn / end_of_your_next_turn / while_exiled durations) |
| Leonardo, Sewer Samurai | FAIL | play_from card spec can't filter by power/toughness ('creature spells with power or toughness 1 or less') and play_from has no 'during your turn' restriction |
| Mosswood Dreadknight // Dread Whispers | PARTIAL | Dread Whispers recast: 'When this creature dies, you may cast it from your graveyard as an Adventure until the end of your next turn' (no casting an Adventure face from outside the hand) |
| Ninja Teen | FAIL | Level 3: granting sneak {3}{B} to creature cards in your graveyard and casting them from the graveyard using sneak: no primitive grants sneak / alternative costs to graveyard cards |
| Null Summoner | FAIL | Conditional ongoing permission ('as long as threshold, you may cast the exiled card') not expressible: play_permission has no condition |
| Omniscience | FAIL | 'You may cast spells from your hand without paying their mana costs' as a static permission: no free-cast static ability (cast_free only works while an effect resolves) |
| Radagast of Rhosgobel | FAIL | 'The first creature spell you cast each turn costs {2} less and can be cast as though it had flash': cost_modifier has no first-spell-each-turn limit and there is no flash-granting permission for spells |
| Raphael, Most Attitude | FAIL | 'you may play a card exiled with Raphael' (a single card) — play_permission can't limit the permission to one card among the exiled ones |
| Tablet of Discovery | FAIL | "You may play that card this turn" for a milled card: play_permission only works for cards in exile, not the graveyard |
| Timeline Culler | PARTIAL | 'You may cast this card from your graveyard using its warp ability' is left out: warp works from the hand only |
| Tinybones, Bauble Burglar | PARTIAL | the play permission for stash cards isn't limited to your turn and doesn't end when Tinybones leaves (play_permission while_exiled per card, not a static ability of Tinybones) |

<a id="3"></a>
## 3. Cost modifiers (15)

**Needs:** `cost_modifier` spell filters by subtype and color; cost increases (self, for targeting this); first-spell-each-turn limit; one-shot "next spell" grants; equip cost reduction; conditions.

| Card | State | Reason |
|---|---|---|
| Arachne, Psionic Weaver | PARTIAL | 'As Arachne enters, look at an opponent's hand, then choose a card type other than creature. Spells of the chosen type cost {1} more to cast.' is left out: cost_modifier can't take a chosen card type (its spells filter only lists fixed types) |
| Don & Raph, Hard Science | FAIL | 'The next noncreature spell you cast this turn has affinity for artifacts': no one-shot effect granting a cost reduction to your next matching spell |
| Dragon's Prey | FAIL | 'This spell costs {2} more to cast if it targets a Dragon': no self cost-increase primitive (cost_reduction only reduces) |
| Dragonlord's Servant | FAIL | cost_modifier spells filter takes card types only; no subtype ('Dragon spells') |
| Dwarven Mauler | FAIL | 'Equip abilities you activate that target this creature cost {2} less': no cost reduction for other permanents' activated abilities conditioned on their target |
| Eluge, the Shoreless Sea | PARTIAL | The cost reduction only takes off generic mana ('{U} (or {1})' becomes {1} per flood land), so it does nothing for a spell with no generic cost. 'The first instant or sorcery each turn' is an amount that becomes 0 once you've cast an instant or sorcery this turn. (Written as reduce = flood lands x (1 - min(1, instants/sorceries you've cast this turn)), where the min is floor((n+99)/100), because divisors must be fixed integers.) Also, a flood land is an Island only while Eluge is on the battlefield (a static on Eluge), not for as long as the counter stays. |
| Hearth Elemental // Stoke Genius | FAIL | cost reduction counts graveyard cards that 'have an Adventure': no card filter for Adventure cards |
| Mistrise Village | FAIL | "The next spell you cast this turn can't be countered": no one-shot uncounterable effect for the next spell |
| Momo, Friendly Flier | FAIL | cost reduction for only the first non-Lemur creature spell with flying cast each turn |
| Radagast of Rhosgobel | FAIL | 'The first creature spell you cast each turn costs {2} less and can be cast as though it had flash': cost_modifier has no first-spell-each-turn limit and there is no flash-granting permission for spells |
| Sunderflock | FAIL | Cost reduction by "the greatest mana value among Elementals you control": no greatest-mana-value amount |
| Temur Battlecrier | PARTIAL | the 'During your turn' limit: the cost reduction also applies to spells cast on the opponent's turn (cost_modifier takes no condition) |
| Terror of the Peaks | FAIL | no cost-increase primitive for opponents' spells that target this permanent (additional life payment) |
| The Fire Crystal | FAIL | cost_modifier can't filter spells by color ("Red spells you cast cost {1} less") |
| Warrior's Blades | FAIL | Equip cost reduction ('This ability costs {1} less to activate for each +1/+1 counter on the creature it targets'): the equip ability takes only `cost`, no cost_reduction |

<a id="4"></a>
## 4. Last-known information (15)

**Needs:** Read power, mana value, counters, attachments and token status of an object after it left the battlefield (destroyed, sacrificed as a cost, died).

| Card | State | Reason |
|---|---|---|
| Azog, Moria's Ruin | FAIL | 'Its controller amasses Goblins X': amass always acts for the ability's controller (no player parameter); also X = destroyed creature's last-known power |
| Bolg of the North | FAIL | damage equal to the sacrificed creature's power: no last-known power of a sacrificed creature (a {result} of the sacrifice is the graveyard card, a token ceases to exist) |
| Donatello, Mutant Mechanic | FAIL | 'put those counters' (every kind of counter the dead artifact had, as it last existed) on a target: add_counters takes one counter kind and counters of the triggering object have no last-known information |
| Feed the Swarm | FAIL | 'You lose life equal to that permanent's mana value' after destroying it: last known information of a destroyed permanent has no mana value (the amount reads 0, scenario-tested; same gap as Seedship Impact). Writing lose_life before destroy validates and gives the same result, but reorders the printed effects |
| Graft Surgeon | FAIL | 'put its counters on up to one target creature': moving all (last known) counters of every kind; add_counters needs one named counter kind (same gap as Zack Fair) |
| Repurposing Bay | FAIL | no amount for the sacrificed artifact's mana value (search for MV = 1 + sacrificed artifact's MV) |
| Rhovanion Rampager | FAIL | 'counters equal to the sacrificed creature's power': no amount for the last-known power of a creature sacrificed by a cost/effect |
| Seedship Impact | FAIL | 'If its mana value was 2 or less' after destroying it: last known information of a destroyed permanent doesn't include mana value (amount reads 0) |
| Sphinx of False Conclusions | FAIL | "When this creature dies, if it isn't a token": no condition can check that the dying source itself wasn't a token (Source condition needs it on the battlefield; triggering-is reads the catalog card, not token status) |
| Tainted Treats | FAIL | 'If its mana value was 4 or less, create a Food' after destroying it: last known information of a destroyed permanent has no mana value (same gap as Seedship Impact); creating the Food before the destroy would change the order |
| The Ooze | FAIL | 'For each +1/+1 counter on it' of a creature that left the battlefield: counters amount of the triggering object has no last-known information |
| Uneasy Alliance | FAIL | '{5}, Sacrifice this Aura: Exile enchanted creature': the `attached` selector finds nothing once the Aura is sacrificed as a cost (no last-known attachment; tested) |
| Unstoppable Slasher | PARTIAL | 'if it had no counters' reads last-known counters, which Enjine may not remember (could return every time) |
| Ygra, Eater of All | PARTIAL | the Food dies trigger relies on last-known types granted by its static (unverified) |
| Zack Fair | FAIL | moving all of its (last known) counters and the Equipment that was attached to it onto the target |

<a id="5"></a>
## 5. Zone-move destinations (search/dig/reveal/return) (15)

**Needs:** `search_library` to graveyard, top of library or exile; `dig`/`reveal_until` with conditional or tapped-and-attacking destinations; return attached to a chosen object.

| Card | State | Reason |
|---|---|---|
| Beseech the Mirror | PARTIAL | the found card goes to your hand instead of exile face down, and when bargained it's cast from your hand (not from exile) without paying its mana cost; otherwise it stays in your hand, as the card says |
| Carnivorous Cultivator // Enroot | FAIL | Enroot: search_library can't put the found card into the graveyard (put supports only hand/battlefield) |
| Deep-Cavern Bat | FAIL | Exile a card from an opponent's hand 'until this creature leaves the battlefield' (until_source_leaves returns cards to the battlefield, not to the owner's hand) |
| Eagle's Rescue | FAIL | return an Aura from the graveyard to the battlefield attached to a target creature: return_to_battlefield has no 'attached to' option (an Aura entering by an effect needs its object chosen, CR 303.4f) |
| Esper Origins // Summon: Esper Maduin | FAIL | Chapter I 'reveal the top card; if it's a permanent card, put it into your hand' (otherwise it stays on top): dig has no rest=top option |
| Insatiable Avarice | PARTIAL | Spree mode 1 'put that card on top' is done as search to hand, then put it on top of the library (search_library can't put onto the library) |
| Lively Dirge | FAIL | Spree with non-targeted 'up to two creature cards with total mana value 4 or less' (no total-mana-value constraint on choose_cards) and search_library putting a card into the graveyard (search_library only puts into hand/battlefield) |
| Loyal Tutor | FAIL | search_library can only put the found card into hand or onto the battlefield; 'shuffle and put that card on top' of the library has no primitive |
| Michelangelo's Technique | PARTIAL | puts at most one creature card with mana value 6 or less onto the battlefield instead of up to two with total mana value 6 or less (dig has no total-mana-value limit) |
| Old Thrush | FAIL | search_library can only put the found card into hand or onto the battlefield; 'shuffle and put that card on top' of the library has no primitive |
| Part in Friendship | FAIL | reveal_until has a fixed destination (put: hand/battlefield); no way to put the revealed creature onto the battlefield or into hand depending on its mana value vs. lands you control |
| Pinnacle Starcage | FAIL | "Put each card exiled with this into its owner's graveyard" (all of them) and count them for Robot tokens: no exile->graveyard move-all effect |
| Raph & Mikey, Troublemakers | FAIL | reveal_until can't put the card onto the battlefield tapped and attacking |
| Shark Shredder, Killer Clone | FAIL | return_to_battlefield can't put the card onto the battlefield tapped and attacking (that player); also no filter for 'that player's graveyard' beyond controller opponent |
| Ugin, Eye of the Storms | PARTIAL | the -11 casts the found cards immediately while the ability resolves (cast_free) instead of at any time until end of turn; the found cards pass through the hand before being exiled (search_library can't exile) |

<a id="6"></a>
## 6. Mana (14)

**Needs:** Once-per-turn limits and choice costs on mana abilities; tapped-for-mana triggers; spend riders (uncounterable, haste); tracking the source of mana; keeping unspent mana.

| Card | State | Reason |
|---|---|---|
| Abzan Devotee | FAIL | mana ability with 'Activate only once each turn': mana abilities take no limit (only only_if) |
| Barrels of Blasting Jelly | FAIL | mana ability with 'Activate only once each turn': mana abilities take no limit (only only_if) |
| Carnelian Orb of Dragonkind | FAIL | mana-spend rider ('if that mana is spent on a Dragon creature spell, it gains haste') not supported |
| Cavern of Souls | FAIL | mana that makes the spell it's spent on uncounterable (spend_only has no such rider) |
| Gene Pollinator | FAIL | Mana ability with a chosen additional cost ('Tap an untapped permanent you control'): mana abilities can't have costs needing a choice |
| Groundchuck & Dirtbag | FAIL | mana trigger 'Whenever you tap a land for mana, add {G}' (no tapped-for-mana trigger) |
| Lavaleaper | PARTIAL | 'Whenever a player taps a basic land for mana, that player adds one mana of any type that land produced' (no mana-tapping trigger in Enjine) |
| Pit of Offerings | PARTIAL | '{T}: Add one mana of any of the exiled cards' colors': no mana ability whose colors come from the cards exiled with it (left out; the land only taps for {C}) |
| Pyre Rhymer // Molten Tide | FAIL | Molten Tide: 'whenever you tap a Mountain for mana, add an additional {R}' — no tapped-for-mana trigger / mana-adding replacement |
| Raphael, Ninja Destroyer | FAIL | mana that isn't lost as steps and phases end until end of turn (add_mana `until` supports only end_of_combat) |
| Scene of the Crime | PARTIAL | '{T}, Tap an untapped creature you control: Add one mana of any color': a mana ability's cost can't need a choice (left out) |
| Secluded Courtyard | PARTIAL | the chosen creature type: the colored mana can be spent on any creature spell or ability of a creature source, not only of the chosen type (card specs can't read a chosen creature type), so the 'choose a creature type' is dropped |
| Springleaf Drum | FAIL | mana ability cost with a choice (tap an untapped creature) is rejected by validation |
| The Last Agni Kai | FAIL | no effect for keeping unspent red mana as steps and phases end until end of turn |

<a id="7"></a>
## 7. Counters (12)

**Needs:** `counters_placed` restricted to counters you put; conditional or computed `enters_with_counters`; static +1 counter replacement; counter doubling; removing a counter of any kind; hone counters.

| Card | State | Reason |
|---|---|---|
| Bristly Bill, Spine Sower | PARTIAL | '{3}{G}{G}: Double the number of +1/+1 counters on each creature you control' is left out: add_counters has no per-creature amount ('its own counters') |
| Drake Hatcher | PARTIAL | 'Remove three incubation counters from this creature': the remove_counters cost can't be limited to this creature, so it may take incubation counters from any creature you control that has them. |
| Dust Animus | PARTIAL | Plot {1}{W} is left out (no plot in Enjine). 'Enters with two +1/+1 counters and a lifelink counter if you control five or more untapped lands' is an ETB trigger that checks the same condition, because enters_with_counters takes no condition. |
| Gev, Scaled Scorch | PARTIAL | 'Other creatures you control enter with an additional +1/+1 counter for each opponent who lost life this turn' is written as a trigger (whenever another creature you control enters, if the opponent lost life this turn, put a +1/+1 counter on it): enters_with_counters with `affects` takes no condition or computed count, so the counter arrives after it enters instead of as it enters |
| Leatherhead, Swamp Stalker | FAIL | 'Remove a counter from her' of any kind (remove_counters effect requires a counter name; the remove_counters cost isn't restricted to self) |
| Michelangelo, Weirdness to 11 | FAIL | counter replacement 'that many plus one +1/+1 counters are put on it instead' (for counters put by any player on creatures you control): only double_counters exists (doubling, controller-only) |
| Miles Morales // Ultimate Spider-Man | PARTIAL | Ultimate Spider-Man's 'Whenever you attack, double the number of each kind of counter on each Spider and legendary creature you control' (no counter-doubling effect) |
| Myojin of Night's Reach | FAIL | conditional 'enters with a divinity counter if you cast it from your hand' (enters_with_counters has no condition) and cost 'remove a counter from this permanent' (remove_counters cost chooses among permanents you control) |
| Putrid Pals | FAIL | Disappear: conditional 'enters with two +1/+1 counters if a permanent left the battlefield under your control this turn' — enters_with_counters has no condition (and amounts can't clamp to 0/2) |
| Sting, Bilbo's Sword | FAIL | hone counters (each grants +1/+0 to the equipped creature) aren't a counter kind Enjine knows; a static reading the counters would emulate the counter's rule |
| The Great Goblin | FAIL | counters_placed can't be restricted to counters *you* put ('Whenever you put one or more counters on a Goblin, Orc, or Army you control') |
| Yoshimaru, Beloved Companion | FAIL | static 'If one or more +1/+1 counters would be put on a creature you control, that many plus one ... instead': counter_bonus exists only as an until-end-of-turn effect covering all counters on all your permanents; no static plus-one counter replacement limited to +1/+1 counters on creatures |

<a id="8"></a>
## 8. Costs & activation limits (12)

**Needs:** Exile-this and exile-a-permanent costs; counters as costs; computed life payment; variable sacrifice; activation limit on equip.

| Card | State | Reason |
|---|---|---|
| Dark Knight's Greatsword | PARTIAL | The 'Activate only once each turn' limit on its equip ability: equip takes no limit. |
| Key to the Side-Door | FAIL | cost 'Discard a legendary card with the same name as a legendary permanent you control' (card spec can't compare names with permanents you control) |
| Madame Null, Power Broker | FAIL | 'you may pay life equal to its power': pay / pay_life take only a fixed integer or announced X, not a computed amount (lose_life would not be a cost and ignores CR 119.4) |
| Mazemind Tome | PARTIAL | 'Put a page counter on this artifact' is paid as the first effect of each ability instead of as a cost; the state trigger 'when there are four or more page counters' is a trigger when a page counter is put on it while it has four or more |
| My Precious // Allure of Power | FAIL | equip with a life-payment cost isn't supported by the guide and was never exercised |
| Myojin of Night's Reach | FAIL | conditional 'enters with a divinity counter if you cast it from your hand' (enters_with_counters has no condition) and cost 'remove a counter from this permanent' (remove_counters cost chooses among permanents you control) |
| Rottenmouth Viper | PARTIAL | the optional additional cost 'sacrifice any number of nonland permanents; costs {1} less for each' (no variable-count sacrifice cost); the blight-counter punishment repeats at most 8 times (once per counter up to 8) because effects can't loop over an amount |
| Sapling Nursery | FAIL | Activated-ability cost 'Exile this enchantment' from the battlefield (no exile-self cost) |
| Shredder's Armor | FAIL | Equip—Sacrifice another nonland permanent with 'Activate only once each turn': the equip ability takes no limit (writing it as a plain activated ability would stop it being an equip ability) |
| The Echoverse Fulcrum | PARTIAL | the activated ability's cost 'Exile The Echoverse Fulcrum' is paid by sacrificing it instead (no exile-this-permanent cost) |
| The Soul Stone | PARTIAL | harness cost 'Exile a creature you control' is paid by sacrificing a creature instead (no exile-a-permanent cost); harnessing is modelled as the Stone gaining the ∞ upkeep trigger for as long as it stays on the battlefield, with the harness ability limited to once (re-harnessing does nothing on the real card) |
| Urban Retreat | PARTIAL | the '{2}, Return a tapped creature you control to its owner's hand: Put this card from your hand onto the battlefield' ability (no return-a-creature cost, no hand-to-battlefield move of the card itself) |

<a id="9"></a>
## 9. Set types / name (become, return as) (11)

**Needs:** `become` / return-to-battlefield that sets (not only adds) card types and subtypes, sets a name, or gives all creature types.

| Card | State | Reason |
|---|---|---|
| Ardyn, the Usurper | FAIL | token copy 'except it's a 5/5 black Demon' must replace creature types; copy `except.subtypes` only adds subtypes |
| Brilliance Unleashed | FAIL | Return a noncreature artifact card and 'it's a 3/3 Robot artifact creature with flying' as it enters: return_to_battlefield can't make it enter as a creature (become only applies after it entered, so creature-enters triggers would miss it) |
| Enduring Curiosity | FAIL | Return to the battlefield as a non-creature ('It's an enchantment') needs removing the creature type indefinitely; become has no set_types |
| Ghost Vacuum | FAIL | no selector for only the creature cards among exiled_with cards (+ enter with flying counter and become 1/1 Spirit) |
| Kitesail Larcenist | FAIL | become effect cannot set card types ('become Treasure artifacts' loses creature type; no set_types on become); per-player target choice |
| Nameless Inversion | PARTIAL | 'loses all creature types until end of turn' is left out (set_creature_types and become need at least one creature type) |
| Oko, Lorwyn Liege // Oko, Shadowmoor Scion | PARTIAL | the -6 ('Choose a creature type. You get an emblem with "Creatures you control of the chosen type get +3/+3 and have vigilance and hexproof"') is left out: an emblem can't remember the chosen type; the +2 gives changeling for 'gains all creature types' |
| Soulstone Sanctuary | FAIL | 'becomes a 3/3 creature with all creature types' (permanent, layer-4 type setting): become has no 'all creature types' form; granting the changeling keyword is an ability, not the same (lost by loses-all-abilities) |
| Supper for Spiders | FAIL | no graveyard-card filter for 'put there from the battlefield this turn', and no way to return cards as Food artifacts that lose all other card types/subtypes (become/return_to_battlefield can't set types) |
| The Irencrag | FAIL | becoming an Equipment with a new name (Everflame) and gaining equip {3}: `become` can't set a name and can't grant an equip ability |
| Zhao, the Moon Slayer | PARTIAL | 'Nonbasic lands enter tapped' (no enters-tapped replacement for other permanents) and the conqueror-counter static making nonbasic lands Mountains that lose their other land types and abilities (no land-type-setting static) |

<a id="10"></a>
## 10. Trigger gaps (extra triggers, Torpor, batched, other events) (11)

**Needs:** `additional_triggers` beyond `you_gain_life`; Torpor-style trigger suppression; batched "one or more" triggers; opponent-searches, spell-becomes-target and discard-this-card triggers.

| Card | State | Reason |
|---|---|---|
| Codie, Ravenous Codex | FAIL | No spell filter for a 'prepared spell' (a prepare-spell copy cast from exile) for the cast trigger |
| Doorkeeper Thrull | FAIL | 'Artifacts and creatures entering don't cause abilities to trigger' (trigger suppression, Torpor Orb style) not supported |
| Great Fierce Bee | FAIL | 'Whenever one or more other creatures die': dies trigger has no batched form; put_into graveyard can't exclude this creature (no 'other') and isn't a leaves-the-battlefield look-back |
| Karn, Argent Defender | FAIL | Torpor-style static 'artifacts and creatures entering don't cause abilities to trigger' has no primitive; the card is otherwise a vanilla 1/3 |
| Katara, the Fearless | FAIL | additional_triggers supports only cause you_gain_life; no 'triggered abilities of Allies you control trigger an additional time' (subject filter); the card is otherwise a vanilla 3/3 |
| Roaming Throne | PARTIAL | 'If a triggered ability of another creature you control of the chosen type triggers, it triggers an additional time': additional_triggers only supports cause you_gain_life |
| Spiritcall Enthusiast // Scrollboost | FAIL | 'one or more tokens enter' written as one trigger per token (approximation) |
| Super Intelligence | FAIL | trigger 'at the beginning of the upkeep of enchanted creature's controller' (step_begins whose is relative to the Aura's controller; no condition comparing the active player with the enchanted creature's controller) |
| Surrak, Elusive Hunter | FAIL | becomes_target trigger for 'a creature spell you control' (becomes_target only watches permanents on the battlefield) |
| Torpor Orb | FAIL | "Creatures entering don't cause abilities to trigger": no trigger-suppression static |
| Wan Shi Tong, Librarian | FAIL | No trigger for 'whenever an opponent searches their library' |

<a id="11"></a>
## 11. Selectors / static filters (11)

**Needs:** `each` scoped to a targeted player; "all other" creatures; attacking and tapped filters in statics; every card in a hand.

| Card | State | Reason |
|---|---|---|
| Avatar's Wrath | FAIL | no selector for 'all other creatures' (each creature except the chosen target) for airbend |
| Dark Leo & Shredder | FAIL | static 'Attacking Ninjas you control have deathtouch': the attacking filter can't be used in a static ability yet |
| Face Yourself | FAIL | token copies 'except it has haste and "At the beginning of the end step, if you don't control a planeswalker, sacrifice this creature"': create_token_copy except can't add a triggered ability; also no selector for 'each creature target player controls' |
| Gnashing of Teeth | FAIL | mode 2 'Creatures target player controls get -1/-1': selector `each` can't be scoped to a targeted player (same gap as Practiced Offense) |
| Hex Magic | FAIL | 'Exile all the cards from your hand': no selector for every card in a hand (choose_cards 'any' is optional, not all) |
| Lost in the Maze | PARTIAL | 'Tapped creatures you control have hexproof' is left out (a static ability can't filter on tapped yet); 'X target creatures' may only be creatures an opponent controls (the card can also tap your own creatures, which then get no stun counter): an effect can't put counters on only the targets you don't control |
| Practiced Offense | FAIL | no selector for 'each creature target player controls' |
| Settle the Wreckage | FAIL | "all attacking creatures target player controls": selector `each` can't be scoped to a targeted player |
| Tishana's Tidebinder | FAIL | Selector for the source permanent of a countered (targeted) ability, to make it lose all abilities, does not exist |
| Turtle Van | FAIL | no target filter for 'creature that crewed it this turn' (and doubling the +1/+1 counters on it) |
| Twisted Fates | FAIL | no selector for 'each creature target player controls' (each-selector can't be scoped to a targeted player) |

<a id="12"></a>
## 12. Replacement effects (10)

**Needs:** Life-gain replacement; others enter tapped; Rest in Peace; filtered token replacement and tripling; draw +1; set or heal damage; exile a countered spell.

| Card | State | Reason |
|---|---|---|
| Angel of Vitality | FAIL | life-gain replacement ('If you would gain life, you gain that much life plus 1 instead') has no primitive |
| Authority of the Consuls | FAIL | 'Creatures your opponents control enter tapped' (enters-tapped replacement for other permanents) has no primitive; enters_tapped is self only |
| Bloodletter of Aclazotz | PARTIAL | the life-loss doubling is approximated: at the beginning of your upkeep (and when it enters during your turn) damage dealt to an opponent is doubled until end of turn. Non-damage life loss isn't doubled, and the doubling lasts the rest of the turn even if Bloodletter leaves |
| Draconic Visitor | FAIL | token_replacement replaces every token; no filter for only artifact tokens ('If one or more artifact tokens would be created') |
| Leyline of the Void | PARTIAL | the opening-hand clause, and the replacement covers only opponents' creatures dying (exile_if_dies) instead of every card going to an opponent's graveyard from anywhere |
| No More Lies | FAIL | counter_unless_pays can't exile the countered spell instead of putting it into the graveyard |
| Quantum Riddler | FAIL | conditional draw replacement 'draw that many plus one' (draw_replacement only multiplies per card, no condition) |
| Rest in Peace | FAIL | Replacement 'if a card or token would be put into a graveyard from anywhere, exile it instead' (exile_if_dies covers only permanents dying) |
| Wolverine, Fierce Fighter | FAIL | Damage replacement 'that damage is dealt, but all other damage already dealt to him is healed' (damage_replacement has no heal-prior-damage option) |
| Zhao, the Moon Slayer | PARTIAL | 'Nonbasic lands enter tapped' (no enters-tapped replacement for other permanents) and the conqueror-counter static making nonbasic lands Mountains that lose their other land types and abilities (no land-type-setting static) |

<a id="13"></a>
## 13. Loyalty abilities (9)

**Needs:** Statics granting loyalty abilities; loyalty-ability activation triggers; instant-speed loyalty; -X loyalty costs.

| Card | State | Reason |
|---|---|---|
| Avatar of Burgeoning Echoes | FAIL | static ability cannot grant loyalty abilities ('Planeswalkers you control have [-10]: ...') |
| Chandra, Chill of Compliance | PARTIAL | Loyalty costs can't be −X, so −X is written as six fixed abilities, 0 (only taps) and −1 to −5 (tap, then put that many stun counters). X ≥ 6 is missing. |
| Gideon the Oathless | FAIL | 'Whenever an opponent activates a loyalty ability': activates_ability has no loyalty-ability-only discriminator (a planeswalker source filter would also match its non-loyalty activated abilities) |
| Jace's Machinations | FAIL | Loyalty abilities activated at instant speed / on any player's turn: no rule-changing effect for loyalty-ability timing |
| Kiora of Salt and Sand | FAIL | static ability granting a loyalty ability to planeswalkers you control ('Planeswalkers you control have [-8]: ...') is not supported |
| Sanctum Lurker | PARTIAL | 'Planeswalkers you control aren't put into their owners' graveyards for having 0 loyalty' and 'Planeswalkers you control have [+2]: ...' (a static can't change the 0-loyalty rule or grant loyalty abilities) |
| Way of the Deathbringer | FAIL | static ability cannot grant loyalty abilities ('Planeswalkers you control have [-2]: ...'), same gap as Avatar of Burgeoning Echoes |
| Way of the Healer | FAIL | static ability cannot grant loyalty abilities ('Planeswalkers you control have [-2]: ...'), same gap as Avatar of Burgeoning Echoes |
| Way of the Pyromancer | PARTIAL | 'Planeswalkers you control have "[+1]: Add {R}."' (a static can't grant loyalty abilities) |

<a id="14"></a>
## 14. Conditions on an earlier effect's result (9)

**Needs:** Filtered result counts and qualities (type of card exiled/discarded this way, whether damage was dealt, whether a card was cast); `if` on delayed triggers.

| Card | State | Reason |
|---|---|---|
| Chandra, Torch of Defiance | FAIL | +1 'You may cast that card. If you don't, ...': cast effect can't report whether the card was cast, so the 'if you don't' branch isn't exact |
| Dalkovan Encampment | FAIL | nested delayed trigger can't name tokens created inside the outer 'whenever you attack this turn' delayed trigger (results_count of delayed effects), so 'sacrifice them' can't be expressed |
| Deadly Brew | FAIL | 'If you sacrificed a permanent this way' needs to know whether YOU (not each player) sacrificed via the shared sacrifice_choice, and 'another permanent card' must exclude the card you sacrificed: no per-player result count nor exclusion of an earlier result |
| Garruk, Veiled Butcher | PARTIAL | −2: you sacrifice first and then the opponent (one after the other instead of at once) so 'if you sacrificed a creature this way' can read your own sacrifice; −3: draws if the opponent discarded fewer than two cards, without checking that the discarded cards were nonland (no filtered result count) |
| Glamdring, Foe-hammer // Gleam of Death | FAIL | Gleam of Death: 'mill six, then put ALL instant and sorcery cards from among them into your hand' - no filtered {result: n} selector; choose_cards count 'any' lets you take fewer (not mandatory) and dig isn't a mill |
| Raven Eagle | PARTIAL | the Clue is created before the exile instead of after (order swapped so the creature-card condition can be read) |
| Seasoned Cryomancer | FAIL | Reflexive trigger needs the number of NONLAND cards discarded by an earlier discard effect (no filtered result count) |
| The Black Arrow | FAIL | 'If a Dragon is dealt damage this way, destroy it': nothing records whether damage was actually dealt (deal_damage's this_way is excess damage), so prevented damage can't be told apart |
| Town Greeter | FAIL | 'If you put a Town card into your hand this way' needs a condition on the quality of the card chosen by an earlier choose_cards effect |

<a id="15"></a>
## 15. Combat (9)

**Needs:** Attacks-alone triggers; defending-player conditions; attack/block taxes; can't be blocked by more than one; attack-count limits; can't be attacked.

| Card | State | Reason |
|---|---|---|
| Howlsquad Heavy | FAIL | 'That token attacks this combat if able': only attacks_each_combat exists, which granted until end of turn would also force attacks in additional combat phases (no per-combat requirement) |
| Jiang Yanggu, Alone | FAIL | trigger 'a creature you control attacks a player alone' (attacks trigger has no alone / defending-player-is-a-player restriction) |
| Loot, the Anomaly | FAIL | 'If his power is negative, he assigns combat damage as though his power were positive' has no primitive |
| Luke Cage, Power Man | FAIL | 'attacks alone' written as a player_attacks trigger, not an attack trigger of the creature (same gap as Spider-Man Noir) |
| Meltstrider's Resolve | FAIL | 'Can't be blocked by more than one creature' (no blocking-count restriction keyword/ability) |
| Preacher of the Schism | FAIL | Trigger condition on the attacked player ('attacks the player with the most life'): attacks trigger exposes no defending player |
| Spider-Man Noir | FAIL | 'Whenever a creature you control attacks alone' has no trigger: attacks triggers fire per creature as it is declared, so a 'only one attacker' check can't be made at declaration end, and player_attacks can't name 'it' |
| The Aetherspark | PARTIAL | 'As long as The Aetherspark is attached to a creature, The Aetherspark can't be attacked' is left out (no can't-be-attacked primitive) |
| Tomik, Orzhov Lawmage | FAIL | 'No more than one creature can attack this planeswalker each combat' (attack-count restriction) has no primitive |

<a id="16"></a>
## 16. Chosen / filtered discard (8)

**Needs:** Discard of a card chosen by another player; discard filters (nonland, keyword).

| Card | State | Reason |
|---|---|---|
| Bandit's Talent | PARTIAL | ETB 'each opponent discards two cards unless they discard a nonland card': the opponent may discard any one card (a land too) instead of two, since a discard effect can't require a nonland card |
| Deceit | FAIL | Second ETB: 'you choose a nonland card from it; that player discards that card' - chosen discard not supported |
| Down, Down to Goblin-town | FAIL | Chapter I: 'You choose a nonland card from it. That player discards that card' - discard chosen by another player is not supported (same gap as Duress) |
| Duress | FAIL | 'You choose a card from their hand; that player discards it' - discard effect has no chooser/card choice (choose_cards put graveyard is not a discard) |
| Oildeep Gearhulk | PARTIAL | the chosen card is put into the graveyard instead of discarded (no chosen-discard effect, so discard triggers don't see it) |
| Solve for Disappointment | FAIL | 'You choose a nonland permanent card from it. That player discards that card.': no chosen-discard primitive (choose_cards put graveyard isn't a discard; same gap as Duress) |
| Steamcore Scholar | FAIL | 'discard two unless you discard an instant/sorcery or a creature card with flying': card spec has no keyword filter |
| Thought-Stalker Warlock | PARTIAL | if the opponent lost life this turn, the nonland card you choose from their revealed hand is put into their graveyard rather than discarded (Enjine has no discard of a card chosen by another player), so discard triggers don't see it |

<a id="17"></a>
## 17. Card names (8)

**Needs:** Choosing a card name; same-name filters; searching graveyard, hand and library by name.

| Card | State | Reason |
|---|---|---|
| Ancestral Anger | PARTIAL | X counts only the base 1: no amount for 'the number of cards named Ancestral Anger in your graveyard' (graveyard filters take no name), so the target always gets +1/+0 |
| Ancient Vendetta | FAIL | Choose a card name; search an opponent's graveyard, hand and library for cards with that name |
| Deadly Cover-Up | FAIL | Collect evidence (CR 701.59) not supported; also searching graveyard/hand/library for cards with that name |
| Key to the Side-Door | FAIL | cost 'Discard a legendary card with the same name as a legendary permanent you control' (card spec can't compare names with permanents you control) |
| Maelstrom Pulse | PARTIAL | 'and all other permanents with the same name as that permanent': no same-name filter; only the target is destroyed |
| Petrified Hamlet | FAIL | Choose a land card name on an ETB trigger; grant mana ability / ban activation for sources with the chosen name (no name filter for chosen names) |
| Sorcerous Spyglass | FAIL | As-enters look at opponent's hand + choose any card name; ban activated abilities of sources with the chosen name (no name filter for cant_activate) |
| The End | FAIL | Search controller's graveyard, hand and library for same-name cards, then draw for each exiled from hand; also a life-total cost reduction |

<a id="18"></a>
## 18. Simultaneous moves (8)

**Needs:** Moving several objects at once (approximations with sequential moves are rejected as inexact).

| Card | State | Reason |
|---|---|---|
| Last Light of Durin's Day | FAIL | hand-and/or-library search split into hand-or-library (approximation) |
| Leonardo's Technique | FAIL | two creatures return one after another, not simultaneously (approximation) |
| Moment of Glory | FAIL | the graveyard branch puts counters on each creature you control, which misses an opponent's targeted creature (approximation) |
| Rush of Dread | PARTIAL | 'sacrifices half the creatures they control, rounded up' is done as one sacrifice at a time (each while they still control at least as many creatures as sacrifices so far +1, which gives the same number, at most 10) instead of all at once |
| Sandman, Shifting Scoundrel | PARTIAL | returns this card and the land card one after the other instead of at once |
| Sphinx's Approach | FAIL | the spell and the four graveyard cards are exiled at different moments, not simultaneously (approximation) |
| Tersa Lightshatter | PARTIAL | the two discards happen one at a time instead of together (a 'one or more cards' discard trigger could fire twice) |
| Troop of Ponies | FAIL | land goes library -> hand -> battlefield and the shuffle happens earlier (approximation of putting one onto the battlefield and one into hand) |

<a id="19"></a>
## 19. Other-player / non-targeted choices (7)

**Needs:** An opponent choosing what to exile; per-player APNAP choices (wheels); non-targeted choice of a permanent on resolution; attach to the triggering object.

| Card | State | Reason |
|---|---|---|
| Clash of Elements | FAIL | The permanent's OWNER decides (top of library or bottom) and is dealt the damage: no owner selector (controller_of differs for stolen permanents) and no follow-up conditioned on the owner's top/bottom choice |
| Quintessential Katana | FAIL | 'you may attach this Equipment to it' (the entering Ninja): attach.to only accepts {target}, self or {result}, not the triggering object |
| Raphael's Technique | FAIL | 'Each player may discard their hand and draw seven': choices in APNAP order then simultaneous discards/draws (CR 101.4); no per-player simultaneous may primitive |
| Strategic Betrayal | FAIL | 'Target opponent exiles a creature they control' (opponent-chosen exile of a permanent) has no primitive (only sacrifice_choice/return_choice) |
| Variable Chaser // Arc of Fortune | FAIL | Arc of Fortune: 'Each player may discard their hand and draw seven cards' needs per-player choices in APNAP order then simultaneous discard/draw (CR 101.4); no per-player simultaneous may primitive (same gap as Raphael's Technique) |
| Vow to Erebor | FAIL | 'you may attach an Equipment you control to it': attach has no non-targeted choice of one Equipment among those you control (attachment is a fixed selector) |
| Winnowing | FAIL | 'For each player, you choose a creature that player controls. Then each player sacrifices all other creatures they control that don't share a creature type with the chosen creature': no non-targeted per-player creature choice and no 'shares a creature type with' filter |

<a id="20"></a>
## 20. Card-type counting (delirium, Goyf) (7)

**Needs:** An amount for the number of card types among cards; kindred and battle nameable in filters.

| Card | State | Reason |
|---|---|---|
| April O'Neil, Hacktivist | FAIL | no amount for 'the number of card types among spells you've cast this turn'; spelling it as one conditional draw per type fails because kindred (and battle) can't be named in a spell filter |
| Fear of Missing Out | FAIL | Delirium: no condition/amount for the number of card types among cards in your graveyard |
| Keen-Eyed Curator | FAIL | 'Four or more card types among cards exiled with this creature' (distinct_types counts creature types, no card-type count amount) |
| Patchwork Beastie | PARTIAL | kindred and battle cards in the graveyard don't count toward delirium's card types (graveyard_card can't name them); delirium is spelled as 'any four of the seven other card types are present' |
| Tarmogoyf | FAIL | no amount for the number of card types among cards in all graveyards (distinct_types counts creature types only) |
| Violent Urge | PARTIAL | delirium counts only artifact, creature, enchantment, instant, land, planeswalker and sorcery (kindred and battle aren't counted: filters can't name them); written as 'any 4 of these 7 types in your graveyard' |
| Wildfire Wickerfolk | PARTIAL | delirium counts only artifact, creature, enchantment, instant, land, planeswalker and sorcery (kindred and battle aren't counted: filters can't name them) |

<a id="21"></a>
## 21. Amounts (library size, greatest MV) (7)

**Needs:** Library-size amount; greatest mana value among a selection.

| Card | State | Reason |
|---|---|---|
| Break Under Pressure | FAIL | "with the greatest mana value among creatures and planeswalkers they control": no greatest-mana-value amount for a sacrifice filter |
| Doomsday Excruciator | PARTIAL | The ETB 'if it was cast, each player exiles all but the bottom six cards of their library face down' is left out: there's no library-size amount. |
| Ill-Timed Explosion | PARTIAL | X is the total mana value of the two discarded cards instead of the greatest (Enjine has no 'greatest mana value' amount); identical whenever one discarded card has mana value 0 (e.g. a land) |
| Jace, Reality Sculptor | FAIL | 0: 'Exile all but the bottom card of each opponent's library' needs a library-size amount (none exists); also the activation condition 'twenty-five or more loyalty counters among Jaces you control' |
| Kitsune's Technique | FAIL | 'mills half their library, rounded up' needs a library-size amount (none exists) |
| Singularity Rupture | PARTIAL | the mill clause: 'then any number of target players each mill half their library, rounded down' is left out (Enjine has no library-size amount) |
| Sunderflock | FAIL | Cost reduction by "the greatest mana value among Elementals you control": no greatest-mana-value amount |

<a id="22"></a>
## 22. Durations (until your next turn / next end step) (6)

**Needs:** `until_your_next_turn` on `become` and keyword grants; `until_your_next_end_step` for play permissions.

| Card | State | Reason |
|---|---|---|
| Absorbing Man | FAIL | become_copy has no 'until your next turn' duration (only end_of_turn/permanent); also the copy exception 'legendary 4/4 Human Villain creature in addition to his other types' with a fixed name |
| Dragonhawk, Fate's Tempest | FAIL | 'until your next end step' play duration and a delayed amount 'each of those cards that are still exiled' not supported |
| Elspeth, Storm Slayer | FAIL | 0 ability: keyword grant 'gain flying until your next turn' (grant/become have no until_your_next_turn duration) |
| Haste Magic | PARTIAL | 'You may play it until your next end step' is modelled as until end of this turn (Enjine has no 'until your next end step' duration); differs only when cast on an opponent's turn |
| Hydro-Man, Fluid Felon | PARTIAL | 'At the beginning of your end step, untap him; until your next turn he becomes a land with {T}: Add {U}' is modelled as an end-step untap plus a static: during turns other than yours he is only a land (no creature type) with '{T}: Add {U}'; Enjine's become has no 'until your next turn' duration, so during your own end step and cleanup he is still a creature |
| Inti, Seneschal of the Sun | FAIL | Play permission 'until your next end step' (only end_of_turn / end_of_your_next_turn / while_exiled durations) |

<a id="23"></a>
## 23. Turn-history conditions (5)

**Needs:** Scried/surveilled, attacked, dealt damage or crewed this turn; "if it's your combat phase".

| Card | State | Reason |
|---|---|---|
| Desperate Futurescribe | FAIL | Condition 'if you've scried or surveilled this turn' has no turn-history amount/condition (no scry/surveil count) |
| Red Guardian, Super-Soldier | FAIL | target 'creature ... that dealt damage this turn': no filter for having dealt damage this turn |
| Supper for Spiders | FAIL | no graveyard-card filter for 'put there from the battlefield this turn', and no way to return cards as Food artifacts that lose all other card types/subtypes (become/return_to_battlefield can't set types) |
| Turtle Van | FAIL | no target filter for 'creature that crewed it this turn' (and doubling the +1/+1 counters on it) |
| Vren, the Relentless | FAIL | 'Creatures exiled under your opponents' control this turn' not countable exactly (exiled_this_turn counts cards exiled from any zone, incl. graveyards) |

<a id="24"></a>
## 24. Owner filters (5)

**Needs:** Filters and selectors for "you own" / the owner.

| Card | State | Reason |
|---|---|---|
| Boiling Rock Rioter | PARTIAL | 'Ally spell from among cards you own exiled with this creature': it can also cast an opponent-owned Ally card it exiled (no owner restriction on exiled_with) |
| Clash of Elements | FAIL | The permanent's OWNER decides (top of library or bottom) and is dealt the damage: no owner selector (controller_of differs for stolen permanents) and no follow-up conditioned on the owner's top/bottom choice |
| Get Out | FAIL | Ownership filter: 'target creatures and/or enchantments you own' (filters only support controller, no owner restriction) |
| Iroh, Tea Master | PARTIAL | the token enters with exactly one +1/+1 counter (for the permanent just given away; written as an enters-with-counters ability on the token) instead of one per permanent you own that your opponents control (no 'owner' filter) |
| Northampton Farm | FAIL | 'Exile target creature you own': filters have no owner restriction (controller only); also the split return (a creature card to the battlefield, each other exiled card to its owner's hand) |

<a id="25"></a>
## 25. Copy exceptions (5)

**Needs:** Copy `except` adding a triggered ability or keeping an ability; copying a card in a graveyard; copy durations.

| Card | State | Reason |
|---|---|---|
| Absorbing Man | FAIL | become_copy has no 'until your next turn' duration (only end_of_turn/permanent); also the copy exception 'legendary 4/4 Human Villain creature in addition to his other types' with a fixed name |
| Ardyn, the Usurper | FAIL | token copy 'except it's a 5/5 black Demon' must replace creature types; copy `except.subtypes` only adds subtypes |
| Face Yourself | FAIL | token copies 'except it has haste and "At the beginning of the end step, if you don't control a planeswalker, sacrifice this creature"': create_token_copy except can't add a triggered ability; also no selector for 'each creature target player controls' |
| Mockingbird | PARTIAL | it may copy only a creature with mana value 1 or less (as if cast for X=0): the 'mana value <= amount of mana spent to cast this creature' bound can't be computed while choosing the copy (the enter_as_copy filter has no source, so mana_spent reads 0) |
| Superior Spider-Man | FAIL | enter_as_copy only copies permanents on the battlefield, not a creature card in a graveyard (plus 'when you do, exile that card') |

<a id="26"></a>
## 26. Modal (per-turn, up to X, repeat) (4)

**Needs:** "Hasn't been chosen this turn"; "choose up to X"; pawprint budgets.

| Card | State | Reason |
|---|---|---|
| Lita, Little Orphan Amphibian | FAIL | modal trigger 'choose one that hasn't been chosen this turn' (`unchosen` remembers modes for the object's lifetime, not per turn) |
| Monument to Endurance | PARTIAL | each trigger may choose any mode: the 'that hasn't been chosen this turn' restriction is missing (unchosen remembers modes for the permanent's lifetime, not per turn) |
| Season of the Burrow | FAIL | pawprint modes ({P} budget of up to five, CR 700.2i) and choosing the same mode more than once: modal spells take only a min/max count of distinct modes |
| The Ruinous Wrecking Crew | FAIL | modal 'choose up to X' (min 0, max X announced): modal choose takes only fixed integers with min >= 1 |

<a id="27"></a>
## 27. Forced retarget (4)

**Needs:** Mandatory change of target of a spell or ability with a single target.

| Card | State | Reason |
|---|---|---|
| Bolt Bend | FAIL | 'change the target of target spell or ability with a single target' not supported (choose_new_targets is optional; no single-target filter) |
| Redirect Lightning | FAIL | 'Change the target of target spell or ability with a single target' (must-change retarget and single-target filter not supported; choose_new_targets is optional) |
| Return the Favor | FAIL | Spree mode 'change the target of target spell or ability with a single target' not supported |
| Untimely Malfunction | FAIL | 'change the target' (mandatory change) of a spell/ability with a single target: only optional choose_new_targets exists |

<a id="28"></a>
## 28. Outside the game (3)

**Needs:** Cards from outside the game.

| Card | State | Reason |
|---|---|---|
| Extrapolate the Impossible | FAIL | Reveal two cards from outside the game; opponent chooses one to put into your hand |
| North Wind Avatar | FAIL | Put a card you own from outside the game into your hand: no effect moves outside-the-game cards to hand |
| Turtles Forever | FAIL | search library and/or outside the game for four legendary creature cards with different names, opponent chooses two for your hand: no outside-game search or opponent-chosen split |

<a id="29"></a>
## 29. Player rules (2)

**Needs:** Player rules for "during combat" / "during your turn", turning off the legend rule, hexproof bypass.

| Card | State | Reason |
|---|---|---|
| Hall of Echoes | FAIL | 'The legend rule doesn't apply to permanents you control this turn': no primitive to turn off the legend rule |
| Nowhere to Run | PARTIAL | 'Creatures your opponents control can be the targets of spells and abilities as though they didn't have hexproof. Ward abilities of those creatures don't trigger' (no hexproof/ward bypass) |

## Unclustered (13)

| Card | State | Reason |
|---|---|---|
| Carnage, Crimson Chaos | PARTIAL | assumes 'self' in the trigger granted by become means the returned creature (untested) |
| Celestial Reunion | PARTIAL | The optional additional cost (choose a creature type and behold two creatures of that type), and putting the card onto the battlefield instead when that cost was paid and the card is of that type. The card always goes to your hand. |
| Compel Brutality | PARTIAL | Mode 2: the spell deals the damage (equal to the planeswalker's loyalty), not the planeswalker, because deal_damage has no source parameter. |
| Emrakul, the Exigent Doom | PARTIAL | Hand ability: exiling Emrakul is part of the effect, not the cost, and the land keeps '{T}: Add {C}{C}' after Emrakul is cast (it should end then). |
| Full Bore | PARTIAL | 'If that creature was cast for its warp cost, it also gains trample and haste until end of turn': cast_with only reads how the source itself was cast, not a targeted permanent, so the rider is left out |
| Garnet, Princess of Alexandria | PARTIAL | 'remove a lore counter from each of any number of Sagas you control' is all-or-none (you may remove one from every Saga with a lore counter, not choose a subset), and the +1/+1 counters are counted from those Sagas just before removing (remove_counters records no amount) |
| Gollum, Riddle Master | PARTIAL | 'mana value of the chosen quality' has no parity filter on the cast trigger: written as two triggers (if odd / if even was chosen) whose spell filter lists mana values 1-15 and 0-16, so an opponent's spell with mana value 17 or more never triggers it |
| Ingris Stingerquill | PARTIAL | the 1 damage to each opponent is dealt by Ingris instead of by the attacking creature (deal_damage has no source selector), so that creature's lifelink/deathtouch etc. don't apply |
| Royal Treatment | PARTIAL | the Role rule (if you control another Role on that creature, it is put into the graveyard): Enjine doesn't enforce one Role per controller per creature |
| Summon: Fenrir | PARTIAL | chapter II: the next creature spell cast this turn doesn't enter with the extra +1/+1 counter; instead, when the next creature you control enters this turn after that cast, it gets a +1/+1 counter (a trigger, and it can hit another creature entering first) |
| The Fire Nation Drill | PARTIAL | '{1}: Permanents your opponents control lose hexproof and indestructible until end of turn' is left out (no effect removes keywords) |
| Thranduil, the Elvenking | FAIL | 'has all activated abilities of all Elf cards in your graveyard' (gaining activated abilities of other cards) has no primitive |
| Uldaros Theorix | FAIL | Targets 'up to one nonland card of each card type' and casting copies with total mana value 6 or less not supported |
