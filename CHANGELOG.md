# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Before 1.0, minor versions may
change the public API; the stable surface is described in
[docs/guides/api.md](docs/guides/api.md).

## [Unreleased]

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
