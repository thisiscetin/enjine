# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
change the public API; the stable surface is described in
[docs/guides/api.md](docs/guides/api.md).

## [Unreleased]

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

[Unreleased]: https://github.com/thisiscetin/enjine/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/thisiscetin/enjine/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/thisiscetin/enjine/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/thisiscetin/enjine/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/thisiscetin/enjine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thisiscetin/enjine/releases/tag/v0.1.0
