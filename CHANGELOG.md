# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
change the public API; the stable surface is described in
[docs/guides/api.md](docs/guides/api.md).

## [Unreleased]

## [0.6.0] - 2026-11-28

### Added
- An activated ability's `cost_reduction` amount may name its targets (`{"counters": {"of": {"target": 0}, "kind":
  "+1/+1"}}`: "costs {1} less for each +1/+1 counter on the target", CR 601.2f); before targets are chosen, it counts as
  any amount for affordability.
- Fuzz invariant: a pending decision always has at least one option.
- Keywords `split_second` (no spells or non-mana activated abilities while it's on the stack, also while another
  object resolves; `spell_keywords` can grant it, CR 702.61), `persist` and `undying` (their dies triggers come with
  the keyword, so statics granting them work and filters see them, CR 702.79a, 702.93a).
- Abilities `offspring` (optional additional cost plus a 1/1 token copy as it enters; `{"cast_with": "offspring"}`,
  CR 702.175), `impending` (`amount`, `cost`: enters with time counters, not a creature while it has one, a counter
  comes off at your end step; `{"cast_with": "impending"}`, CR 702.176a), `miracle` (the first card drawn this turn
  triggers and may be cast for its miracle cost as the trigger resolves; `cards_have` with `zone: "hand"` grants it,
  CR 702.94a) and `craft` (`cost`, `materials`: exile this and permanents you control and/or graveyard cards, return
  it transformed; materials are `exiled_for_cost`, CR 702.167).
- Cost `collect_evidence` (exile graveyard cards with total mana value N or more, CR 701.59); "if evidence was
  collected" is an optional `additional_cost` read by `{"cast_with": "additional_cost"}`.
- Condition `{"void": true}` (a nonland permanent left the battlefield or a spell was warped this turn).
- `flashback` takes `cost: "mana_cost"` (its flashback cost equals its mana cost; e.g. granted by `grant_ability`,
  CR 702.34a). `warp` takes `from: ["hand", "graveyard"]` (CR 601.3).
- `cycling` takes a cost with {X} or a list of costs ("Cycling—Pay 2 life"); trigger `cycles` takes `self: true`
  ("when you cycle this card", a `zone: "graveyard"` ability whose X is the cycling ability's, CR 702.29c).
- Battles (CR 310): card type `battle` with a printed `defense` (it enters with defense counters, CR 310.4b) and the
  battle type `siege`: an opponent becomes its protector as it enters (CR 310.12); the protector's opponents can
  attack it and the protector blocks for it (CR 310.5, 310.9); damage removes defense counters (CR 120.3h); at 0
  defense it's put into its owner's graveyard unless its triggered ability is still waiting (CR 704.5v); a Siege its
  protector controls gets a new protector (CR 704.5x); defeated, a Siege exiles itself and its controller may cast its
  back face without paying its mana cost (CR 310.12, 712.10). Filter `battle`; `any_target` now includes battles
  (CR 115.4); views show `defense` and `protector`.
- Ability `life_gain_replacement` (CR 614.1a, 616.1): "if you would gain life, you gain twice that much / that much
  plus 1 instead" (`multiply` / `plus`) and "if an opponent would gain life, that player loses that much life
  instead" (`player: "opponent"`, `lose: true`).
- `choose_cards` takes `chooser` (a player selector: "target opponent chooses a card from among them", CR 608.2d; that
  player looks at hidden cards first) and `count: "all"` (every matching card, no choice: "discards all cards with
  that name").
- Card specs take `"name": "chosen"` (the card name chosen for the source or the resolving spell, CR 201.4): in
  the card specs of resolving effects (`reveal_until`, `exile_top` `until`, `choose_cards`, `search_library`, ...) and
  in `cost_modifier` `spells` (which takes `name` now), `player_rule` `spells` ("spells with the chosen name can't be
  cast") and `grant_ability` `for`. Like `"subtypes": "chosen"`, it matches nothing in specs read without a source
  (`play_permission`, `cards_have`, `convoke`, mana-ability spends, `cant_be_targeted_by` `abilities_from`).
- Triggers: `enters` and `dies` take `batched` ("whenever one or more ...", CR 603.2c); `deals_damage` takes `batched`
  and `to` as `you`, `planeswalker`, `battle`, `permanent` or a list of them. A batched trigger's
  `{"triggering": "objects"}` names the objects of every occurrence in its batch ("those creatures").
- `remove_counters` and `remove_all_counters` reach players' counters (poison, energy, experience, CR 122.1).
- Spell filters accept the card types `kindred` and `battle` (CR 308, 310).
- Static abilities may read combat and tapped status: `affects` with `{"creature": {"attacking": true}}`, `blocking`,
  `tapped`, and an `if` such as `{"attacking": "attached"}` ("as long as equipped creature is attacking", CR 506.4).
- Committing a crime (CR 700.13): a spell cast, ability activated or triggered ability put on the stack that targets
  an opponent, something an opponent controls or a card in an opponent's graveyard is one crime (activated and
  triggered abilities count, not only spells). Trigger `commits_crime` (`controller`), amount `crimes_this_turn`,
  event `crime_committed`.
- Cases (CR 720.3, 702.169): ability `to_solve` (a condition; at the beginning of your end step the Case becomes
  solved), ability `solved` wrapping one static, triggered or activated ability, effect `solve`, condition
  `{"solved": true}`. Solved is a permanent designation shown in views (`designations`).
- Harness and ∞ (CR 701.64, 702.186): effect `harness`, ability `infinity` wrapping one static, triggered or
  activated ability, condition `{"harnessed": true}`; cost `exile_permanent` ("Exile a creature you control", not a
  sacrifice; the cards are `exiled_for_cost`, their last known stats amount `sacrificed`).
- Ninjutsu (CR 702.49): an activated ability from the hand (not a cast): pay, reveal the card, return an unblocked
  attacker; the card enters tapped and attacking what that creature attacked. Usable from the declare blockers step
  to the end of combat.
- Rooms (CR 709.5, 116.2m): layout `room` (two doors sharing a type line). The card has both halves combined off the
  battlefield, is cast as one door, and the permanent has only its unlocked doors' name, mana cost and abilities
  (both locked: no name, mana value 0). Special action `{type: "unlock", object, door: "left" | "right"}`; trigger
  `unlocks_door` (on a door: "when you unlock this door"; `door: "any"`, `fully: true`); views show `unlocked`.
- Face-down spells and permanents (CR 708): effects `manifest`, `cloak` and `manifest_dread` (CR 701.40, 701.58,
  701.62); keyword abilities `morph` and `disguise` (cast face down for {3}, CR 702.37, 702.168); special action
  `{type: "turn_face_up", object, via: "mana_cost" | "morph" | "disguise"}` (CR 116.2b); trigger `turned_face_up`;
  amounts `entered_face_down_this_turn` and `turned_face_up_this_turn`. A face-down object is a nameless 2/2 (ward {2}
  for cloak and disguise) with an id that doesn't name it; only its controller sees the card in views and events,
  and it is revealed when it leaves the battlefield or stack and at the end of the game (CR 708.5, 708.9).
- Repeated keyword instances: `"keywords": ["cascade", "cascade"]` gives two cascade abilities that each trigger
  (CR 702.85c); the same for `storm`, `extort` and `increment` (CR 702.40b, 702.101b, 702.191b). Other keywords
  listed twice stay one instance (CR 702.2f).
- Effect lists nested in `may`, `pay`, `choose_cards`, `reflexive_trigger` and `delayed_trigger` number their own
  results after the enclosing list's earlier effects: in a list nested in effect `i`, `{"result": n}` and
  `{"this_way": n}` with `n < i` name the parent's effects as before, `i + j` the nested list's own effect `j` (a
  `may`'s `then` continues after its `effects`; CR 608.2c, 603.12).
- `{"counters": {"of": {"triggering": "object"}}}`, and `power`, `toughness` and `mana_value` of `{"triggering":
  "object"}`, read a permanent that left the battlefield as it last existed (CR 603.10a, 608.2h).

### Changed
- Faster legal options, with identical results (the same options in the same order, the same random numbers drawn):
  while one decision's options are computed, a conservative mana pre-check rules out spells whose colored symbols the
  player's mana can't reach (CR 601.2f-h) and costs above what the player could ever make; permission sources, play
  methods, cost modifiers, battlefield characteristics and abilities by kind are found once per decision; exiled cards
  of another owner no permission names are skipped (CR 108.3); cards with no face that has an alternative cost or a
  special action skip the full look (`Engine::OptionsMemo`).
- `Game#view_for` reuses the pending decision's memoized options instead of generating them again
  (`View.build` takes `options:`); views reuse each card's type line, mana cost text and keyword names (now frozen
  strings), and `Snapshot.deep_copy` / `State#to_h` copy plain data without a Marshal round trip.
- `script/determinism_digest.rb`: plays seeded games (constructed example and random decks, the real cards, Duel
  Commander) and prints a digest per game of every decision's options, views, export/import, rolled-back applies and
  forks, to check that a performance change keeps games bit-identical.

### Fixed
- `pay` (and `counter_unless_pays` with `cost`): a cost's choices keep every key of the option, so `remove_counters`
  removes the chosen counter kind (it removed nothing and still counted as paid), and `choose_creature_type` then
  `behold` `"subtypes": "chosen"` work while resolving (the resolving spell or ability remembers the type, CR 118.12).
- `pay` in a triggered or activated ability: "this permanent" costs (`remove_counters` `self: true`, `sacrifice`,
  `other: true`) refer to the source permanent while it is still on the battlefield under the ability's controller,
  not to the ability on the stack (CR 113.7a); once it has left, they can't be paid (CR 400.7).
- `exile_this_spell` may come before effects that ask for a decision or pay, and before a `reflexive_trigger`: the
  resolving frame keeps the spell as it last existed on the stack and it stands in for itself until it has resolved
  (CR 608.2n; it raised `KeyError`). Snapshots and their validation keep it (`left_stack` in the resolve frame).
- `cost_modifier` `spells: {"subtypes": "chosen"}` reduces the cost of spells of the type chosen for the permanent
  (CR 607.2d; it never applied).
- A granted mana ability's `{"tap": "granter"}` cost taps the granting permanent; affordability counts such abilities
  as one source among all of them, and cancelling a payment untaps the granter (CR 602.2b, 607.1a, 734.1).
- A payment made irreversible by a mana ability (paying life, sacrificing) that can no longer be finished offers
  `cancel` instead of no option at all: the cast is rewound (or the resolving payment counts as unpaid), the mana
  abilities aren't (their sources stay tapped, their mana stays in the pool) and the mana spent goes back to the pool
  (CR 734.1).
- A `one_of` in a mana ability's cost is refused when the card is loaded (it crashed when activated, CR 605.3a).
- "Target ... with mana value X" reads the X of the spell or ability being cast (CR 601.2b-c, 608.2b), not its
  source's.
- Permanents put into graveyards by the same state-based-action check are one event batch for "one or more"
  triggers (CR 603.2c, 704.3); before, each was its own batch. Combat damage of one step is named as one batch
  explicitly (CR 510.2).
- `cost_modifier` `spells` with `"subtypes": "chosen"` now reads the source's choice (it never matched before).
- An additional trigger of a batched ability no longer shares its "that many" count with the original.
- `"self"` in a permanent's own leaves-the-battlefield trigger finds the card in the public zone it went to while
  it's still there, so "when this dies, exile it / return it" works (CR 400.7e); amounts of `"self"` still read it
  as it last existed.
- A token copy of a card counts as a token in `{"triggering": filter}` conditions (CR 111.1).
- A dies trigger of a permanent that was cast remembers how (`was_cast`, `cast_from` / `cast_with`, kicker, the
  mana spent); `was_cast` and `cast_from` / `cast_with` also work as its intervening "if" (CR 400.7d, 603.4).
- `{"triggering": "object"}` names the permanent of a `becomes_untapped` trigger (CR 603.2).
- A reflexive trigger's `{"this_way": n}` reads its own effects' amounts, not the creating list's.
- Color identity counts the colors of a mana choice among some (`"color": "any_one", "colors": ["B", "G"]`), and
  no longer counts mana of the chosen color (a fixed color gated by `"only_if": {"chosen": ...}`, CR 903.4).
- `RulesMonitor` reads a permanent's types, keywords and abilities from the engine's layers 1-6 (CR 613.1a-f)
  instead of re-deriving them from the printed card, and recomputes only layer 7 and the rules that follow. No more
  false findings for: statics matching a creature that "becomes a Bear in addition to its other types" (CR 205.1b,
  613.4c); a creature an effect made only a land (CR 208.3); keyword counters (an indestructible counter, CR 122.1b,
  704.5g); a copy's `except` keywords (haste on a token copy, CR 707.9b, 302.6); keywords an Aura granted before a
  "loses all abilities" effect (timestamps, CR 613.7, 702.9b); extra land plays from a class level or a station symbol
  (CR 305.2, 717.2a, 722.2a); "no maximum hand size" from an emblem (CR 114.4, 514.1). It also counts every
  power/toughness counter (`-0/-1`, `+1/+0`, ..., CR 122.1a) and checks a `"-X"` loyalty ability against the X
  announced (CR 606.4, 107.3).
- `Enjine::Verify` places a colorless land with a colored activated ability or cycling cost in a coverage deck whose
  colors cover it, instead of failing to build one ("does not fit a … deck") and never exercising the land.

## [0.5.0] - 2026-11-24

### Added
- Casting permissions: `play_permission` `duration: "while_you_control_source"` ("for as long as you control this
  creature", CR 611.2b), `during: "your_turn"` and `waterbend: "mana_value"` (cast by waterbending {X}, CR 701.67a);
  `cast` and `cast_free` take `from` (e.g. `"graveyard"`), `cast` takes `exile_instead` (CR 608.2g), `cast_free` takes
  `count` as an integer ("up to three").
- Ability `cards_have`: cards you own in a zone have a keyword alternative cost (flashback, harmonize, mayhem,
  web_slinging or sneak) and may be cast with it ("Creature cards in your graveyard have sneak {3}{B}", CR 611.3a);
  cast option `via: "alt:cards_have:<permanent>:<ref>"`.
- Costs: an optional `additional_cost` with `flash: true` ("as though it had flash if you behold a Dragon", CR 601.3c);
  `choose_creature_type` before `behold` with `"subtypes": "chosen"` (CR 607.2d); `exile_from_graveyard` with
  `count: "any"` and `symbols` (a mana-symbol total, CR 107.4e), and `copy_card` `of: "exiled_for_cost"`; `pay_life`
  with a computed amount (`{"power": "self"}`, e.g. in ward); `remove_counters` with `self: true` and `count`.
- Card specs take `same_name_as` (a filter: "with the same name as a legendary permanent you control", CR 201.2a)
  and `"subtypes": "chosen"`. `search_library` takes `battlefield_instead` (`if`, `for`).
- Triggers: `gives_gift` ("whenever you give a gift", CR 702.174c); `cast` with `owner: you | not_you` ("a spell you
  don't own", CR 108.3); `attacks` with `alone: true` (CR 506.5); `counters_placed` with `nth` ("when the fourth plan
  counter is put on it", CR 122.6).
- Effects, zones and loops: `repeat` (`effects`, `while`: "repeat this process", CR 608.2c), with `{"result": n,
  "for": card spec}` selectors; `exile_top` `until` (`{"total_mana_value": n}` or `{"card": spec}`, CR 406.1);
  `cast_free` `count: "any"`; `choose_cards` `random: true`; target filter `exiled_with` (a card this object's
  abilities exiled, with `link: true` on `exile`, `choose_cards`, `dig`, `exile_top` and `exile_if_dies`, CR 607.2a);
  condition `attacking` ("if it was attacking", CR 608.2h); stack filters `single_target`; effect `change_target`
  (CR 115.7a); `dig` `looker: "source_controller"`.
- Statics, grants and combat: cost `{"tap": "granter"}` in a granted ability (CR 602.2b, 607.1a); `become`
  `colors: "chosen"` with `hexproof_from: "chosen_color"` bound into the granted ability (CR 607.2d); keyword
  `cant_become_untapped` (CR 701.26b); the `choose_card_name` ability takes `types` and `look_at_hand`, and is now
  an effect too (`remember: "source"` for every resolving `choose_*`); `"name": "chosen"` in filters and in
  `player_rule` `cant_activate` (CR 201.4, 602.5); `player_rule` `cant_be_attacked` with a `filter` (CR 508.1c);
  statics can grant `cant_be_blocked_by`, and `become` can grant `tapping_power`; `create_token` `size` (an N/N
  token, CR 707.2); riot granted by a static ability is chosen as the permanent enters (CR 614.12, 702.136b).
- Decision `damage_order` (CR 616.1): when the order of replacement and prevention effects on one damage event
  changes the result, the affected player chooses it. Agents must answer this new decision kind.

### Changed
- `choose_new_targets` and `copy_spell` targets become targets (ward and `becomes_target` trigger, CR 115.7, 707.10);
  new targets of a divided spell keep each target's share (CR 115.7f); `prevent_damage` `by: "chosen_source"` may
  choose spells, abilities and command-zone objects (CR 609.7a-b); tokens created attacking choose a planeswalker to
  attack when there is one (CR 508.4); "copy that ability" after it left the stack copies it as it last existed.
- A hidden-away card may be looked at and played by whoever controls the permanent now (CR 702.75a); earthbend's
  return ends when the land leaves for another zone; a melded permanent's mana value is its front faces' total
  (CR 713.5c).

### Fixed
- A card's colors include those of its hybrid symbols (CR 202.2d): a `{U/B}` card is black for `"colors": ["B"]`.
- "Damage can't be prevented" against a prevention effect with `then`: it still applies once without preventing
  anything (CR 615.12).
- The rules monitor accepts a spell cast at instant speed through its paid flash-granting additional cost (CR 601.3c).

## [0.4.1] - 2026-11-22

Includes 0.4.0, which was tagged but never published to RubyGems.

### Added
- `become` takes `set_types` ("it's an artifact, not a creature", CR 205.1a), `"creature_types": []` ("loses
  all creature types") and `all_creature_types: true` (CR 205.3d).
- `return_to_battlefield` takes `as`: the `become` changes it has from the moment it enters ("It's an
  enchantment. (It's not a creature.)", CR 614.1c), seen by abilities that trigger on it entering.

### Changed
- Faster legal options and state-based actions, same behaviour: a random-agent game runs about 2.3x as many
  decisions per second on the fixture pool and 1.7x on the real-card fixtures. Off-board characteristics are
  memoized per decision; cards that can't be played or activated from their zone are skipped
  (`CardDefinition#plays_itself?`, `#activation_zones`); the token scan and graveyard trigger watch are cached
  while no object appears, moves or ceases to exist.

### Fixed
- The trigger condition `{"triggering": filter}` matches a permanent that left the battlefield with the card
  types it last had ("if it was a creature", CR 603.10a), not its printed ones.
- The rules monitor's power/toughness check (CR 613.4c) leaves out permanents whose card types were set.

## [0.4.0] - 2026-11-21

### Added
- `counters_placed` takes `by: you | opponent` ("whenever you put counters", CR 122.6a); the
  `counters_changed` event carries `by`, the player who put them.
- Filters take `owner: you | opponent` ("a creature you own", "creatures you control but don't own",
  CR 108.3), in targets, selectors and statics.
- Card specs take `keywords`, `not_subtypes`, `power`, `toughness` and `layout` ("a creature card with
  flying", "a non-Avatar card", "power 1 or less", "a card that has an Adventure").
- Durations counted in your own turns: `become_copy` `until_your_next_turn`, `gain_control`
  `end_of_your_next_turn`, `play_permission` `until_your_next_end_step` (CR 611.2a).

### Changed
- `owner` is refused, with a validation error, where a filter matches characteristics only (card specs
  in zone-change triggers, cost modifiers, replacement effects, counted values), instead of being ignored.

## [0.3.0] - 2026-11-20

### Added
- Duel Commander (CR 903): `Enjine::Setup.new(alice, bob, format: :duel_commander)`
  (`Enjine::Format`). Commanders start in the command zone, players start at 40 life,
  a commander is cast from the command zone with `via: "command"` and pays the commander
  tax, a new `commander_zone` decision lets its owner return it to the command zone
  (903.9a–b), and 21 combat damage from one commander loses the game (reason
  `"commander_damage"`).
- Deck documents take `"commander"`. `Deck#errors(format)`, `Deck#valid?(format)` and
  `Player#ready?(format)` check a deck against a format. Commander decks need exactly
  100 cards, singleton, and color identity.
- `CardDefinition#color_identity`, derived from the card's data across all faces;
  the card field `color_identity` overrides it.
- `DeckBuilder#build(commander:)` builds Duel Commander decks; `Fuzz.random_commander_deck`;
  `rake fuzz[games,seed,duel_commander]`; the CLI's `--format`.
- Views show the command zone's commanders and, per player, `commander`,
  `commander_tax` and `commander_damage`.

### Changed
- Only emblems' abilities function from the command zone (CR 113.6, 114.4); the
  command zone may now also hold commanders.
- `State::STARTING_LIFE` is gone: starting life comes from the format.

## [0.2.0] - 2026-11-12

### Added
- Amounts `card_types` (how many card types among cards: delirium, "*" power),
  `greatest_mana_value` and `library_size` ("half their library, rounded up").
- Amount `sacrificed` (`power`, `toughness` or `mana_value` of the permanents sacrificed to pay the cost).
- `choose_cards` `put: discard`: the owner discards the cards chosen from their hand ("you choose a
  nonland card from it; that player discards that card").
- `mana` abilities take `limit: "once_each_turn"`.
- `cost_modifier` `spells` takes `subtypes` and `colors` ("Dragon spells", "red spells").
- `grant` and `become` take `duration: "until_your_next_turn"`.
- Cost `exile_self` ("Exile this enchantment: …").
- `additional_triggers` takes `of`, a filter of the permanent whose ability triggers; `cause` is optional.
- Plot (CR 702.170): ability `plot` (a special action from the hand) and effect `plot` ("it becomes
  plotted"); a plotted card is cast from exile for free on a later turn with `via: "plotted"`.
- Statics can grant loyalty abilities; loyalty abilities take `cost: "-X"`; `activates_ability` takes
  `loyalty: true`.
- `search_library` `put: graveyard`, and `put: library_top` ("then shuffle and put that card on top").

### Fixed
- Power, toughness and mana value of a permanent that left the battlefield while the spell or ability
  resolves are read as it last existed (CR 608.2h): a destroyed target, or `{"result": n}` of a sacrifice.
  They read 0 or the card's printed values before. A reflexive trigger ("when you do") reads them too.
- `search_library` works out computed bounds in `for` ("mana value equal to 1 plus …"); such a search
  found nothing before.
- A characteristic-defining power/toughness that counts cards in graveyards no longer recurses forever
  while its own card is in a graveyard.

## [0.1.0] - 2026-11-11

### Added
- Two-player game engine pinned to the 2026-11-06 Comprehensive Rules: turn
  structure, priority, the stack, casting with manual mana payment, combat,
  state-based actions, layers, replacement and prevention effects, copies,
  London mulligan.
- Atomic decision API (`Game#pending_decision`, `submit`, `apply`), per-player
  views and histories, export/import of any moment, `fork`, deterministic replay.
- Card DSL: cards as JSON data, validated with path-addressed errors; the
  mechanics of the Standard-legal sets (Foundations to Star Trek).
- `Enjine::DeckBuilder` (random decks from a card pool), `Enjine::RulesMonitor`,
  `Enjine::Fuzz` and `Enjine::Verify`.
- `enjine` CLI: hot-seat and random play, `--validate`, `--verify`,
  `--random-deck`, save and load.

[Unreleased]: https://github.com/thisiscetin/enjine/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/thisiscetin/enjine/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/thisiscetin/enjine/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/thisiscetin/enjine/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/thisiscetin/enjine/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/thisiscetin/enjine/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/thisiscetin/enjine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thisiscetin/enjine/releases/tag/v0.1.0
