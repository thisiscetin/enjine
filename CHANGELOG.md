# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
change the public API; the stable surface is described in
[docs/guides/api.md](docs/guides/api.md).

## [Unreleased]

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
- `search_library` `put: graveyard`, and `put: library_top` ("then shuffle and put that card on top").

### Fixed
- Power, toughness and mana value of a permanent that left the battlefield while the spell or ability
  resolves are read as it last existed (CR 608.2h): a destroyed target, or `{"result": n}` of a sacrifice.
  They read 0 or the card's printed values before.
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

[Unreleased]: https://github.com/thisiscetin/enjine/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/thisiscetin/enjine/releases/tag/v0.1.0
