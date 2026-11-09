# Star Trek (`trk`) mechanics

Goal: the engine supports every mechanic that Star Trek cards use, so you can
write any `trk` card yourself in the [card DSL](../guides/card-data-format.md).
Enjine ships no card data and never reads card text.

Every mechanic is tested with invented cards (unit, integration and fuzz through
`spec/fixtures/cards/`). The notes below record how each Star Trek
mechanic is implemented and which rules it cites.

## Set mechanics

Rule numbers follow the pinned **2026-11-06** CR, the first version that
defines assimilate. The "2026-09-25" column records how the previous CR
numbered (or lacked) each rule.

| Mechanic | Rules used (2026-11-06) | 2026-09-25 | Card data | Status |
| --- | --- | --- | --- | --- |
| Station | 702.184a, 722.2a-c, 722.4, 302.6 | 721.x (same subrules) | keyword `station` (an intrinsic activated ability, ref `keyword:station`) + `station_symbol` abilities `{"at": N, "power", "toughness", "keywords", "abilities"}` | done |
| Tap another creature (the station cost) | 702.184a, 601.2h, 602.2b | same | cost `tap_another_creature`, decision `choose_cost` | done |
| Sagas | 715.2b-d, 715.3a, 715.3c, 715.4, 704.5s, 505.4, 122.6 | 714.x (same subrules), 704.5s, 505.4 | subtype `saga` + `chapter` abilities `{"chapter": N, targets, effects/modes}` | done |
| Face a dilemma | 700.17 | not in this version | trigger `faces_dilemma {"controller"}` | trigger done |
| Assimilate | 701.72a-b, 205.1b | not in this version | effect `assimilate`; filter `graveyard_card` | done |
| Strange new worlds | 207.2c (ability word: no rules meaning) | not listed | amount `{"distinct_names": selector}` | count done |
| Beam me up | 702.196a-b, 118.9, 601.2b, 601.2f-h | not in this version | ability `beam_me_up {"cost"}`, static `grants_beam_me_up`, flag `cant_be_beamed_up`; cast option `via: "beam:<ref>"`; the creature is a `choose_cost` decision, returned as the spell becomes cast | done |
| Casting from other zones | 601.3, 113.6e-f, 305.1, 401.5, 608.2g, 701.57 | same numbers | ability `play_from`, `look_at_top`; effects `exile_top`, `exile_until`, `play_permission`, `cast_free`, `discover`; permissions are `state.effects` of kind `permission` | done |

How they work:

- **Station symbols** apply in the layer pass from the permanent's own charge
  counters (`Engine::Characteristics#own_layers`): layer 4 adds the creature type,
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
  independent P/T check.

## Costs, mana and targets

Rule numbers from the pinned 2026-11-06 CR.

| Capability | Rules | Card data | Status |
| --- | --- | --- | --- |
| Hybrid mana `{R/G}` | 107.4e, 202.2d, 202.3f, 601.2h | mana costs; each symbol paid by either color | done (monocolored hybrid `{2/B}` and Phyrexian: todo) |
| Cancelling a cast | 734.1, 605.3 | — | "cancel" only until something irreversible is paid (a Treasure's sacrifice); from then on only payments that keep the rest payable are offered |
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

Still waiting on other capabilities: Marooned (can't be beamed up, "doesn't untap"), Pure Energy (beam me up),
Worf, Honor-Bound Warrior (power doubling, total power), Engineered Explosives (mana value equal to an amount; the
sacrificed source's counters are kept in the ability's memory `source_counters`), Starfleet Academy (creature-type
count; a mana ability with a variable amount and color choice), Commander Raffi Musiker, Daniels, Temporal Agent
and Emergency Holographic Crew (exiling or returning cards from a graveyard).

Trigger capabilities (group 4: becomes tapped, counters put, becomes the target, leaves a
graveyard, activates an ability, cast filters and chosen values, once each turn, additional
triggers, created and reflexive triggers, `may` decided by another player, as-enters number and
card-name choices, enters tapped unless, enters untapped triggers, another counter of a kind).

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

### Zone effects: library, hand, graveyard, edicts, linked exile

Primitives: `dig` (look at or reveal the top N, take
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

`RulesMonitor#keyword?` now counts keywords granted by static abilities (haste from Hit It!,
flying or reach), so trk games with those grants no longer report false 302.6 / 702.9b findings.
