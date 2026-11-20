# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
change the public API; the stable surface is described in
[docs/guides/api.md](docs/guides/api.md).

## [Unreleased]

### Added
- `counters_placed` takes `by: you | opponent` ("whenever you put counters", CR 122.6a); the
  `counters_changed` event carries `by`, the player who put them.
- Filters take `owner: you | opponent` ("a creature you own", "creatures you control but don't own",
  CR 108.3), in targets, selectors and statics.
- Card specs take `keywords`, `not_subtypes`, `power`, `toughness` and `layout` ("a creature card with
  flying", "a non-Avatar card", "power 1 or less", "a card that has an Adventure").
- Durations counted in your own turns: `become_copy` `until_your_next_turn`, `gain_control`
  `end_of_your_next_turn`, `play_permission` `until_your_next_end_step` (CR 611.2a).

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

[Unreleased]: https://github.com/thisiscetin/enjine/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/thisiscetin/enjine/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/thisiscetin/enjine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/thisiscetin/enjine/releases/tag/v0.1.0
