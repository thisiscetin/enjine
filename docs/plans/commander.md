# Plan: Duel Commander (0.3.0)

**Goal.** Enjine plays Duel Commander: two players, 100-card singleton decks led by a
commander, 40 life (CR 903). Commander is a *game-setup variant*: `DESIGN.md` §1 now
lists it as in scope. Which card mechanics we implement is still governed by the
Standard program.

## Decisions (settled with the user)

- **Format.** Duel Commander only: 1v1, 100 cards including the commander, 40 life.
  Multiplayer Commander and Brawl are separate, later work.
- **Rules in the cut.** Command zone for commanders (903.6), life 40 (903.7), tax (903.8),
  returning to the command zone (903.9a, 903.9b), 21 combat damage from one commander
  (903.10a), deck construction (903.3–903.5).
- **Deferred (OOS in `MECHANICS_COVERAGE.md`).** Partner, background, companion, commander
  ninjutsu, "can be your commander" on non-creatures, cards that refer to "your commander".
- **Commander picked up front.** The deck carries `"commander": "Card Name"` beside `main`
  (99 cards + the commander). The format is a `Setup`/`Game.start` option; the default stays
  constructed and unchanged.
- **Engine knows no banlist.** It validates structure only: 100 cards, singleton, color
  identity, a legal commander card.
- **Color identity** is derived from structured card data (never rules text), with an
  optional explicit `color_identity` override.
- **Identity of the commander** is a predicate (owner + the card's own id, not a token, not a
  copy), never a flag on the object, so zone changes and cancelled casts can't lose it.

## Design

| Piece | Where |
| --- | --- |
| Format presets | `Enjine::Format` (`CONSTRUCTED`, `DUEL_COMMANDER`) |
| Color identity | `Enjine::ColorIdentity`, `CardDefinition#color_identity` |
| Deck validity per format | `Deck#errors(format)`, `Deck#commander` |
| Per-game config | `State#format`, `State#commanders`; `PlayerState#commander_casts`, `#commander_damage` |
| Rules | `Engine::Commander` (setup, predicate, casting method + tax, damage, 903.9) |
| Cast from the command zone | a play *method* (`via: "command"`) with a `cost_increase` rider: tax is part of the cost |
| 903.9 choice | `Decisions::CommanderZone` + a `commander_zone` frame, like the legend rule |
| 21 damage | counted in `deal_proposed_damage!`, checked as a state-based action |

Command-zone cards that are not emblems have no abilities that function there
(CR 113.6): `Engine#emblems` is the one accessor for "objects in the command zone that act".

## Open point: 903.9b

903.9b is an optional *replacement* ("would be put into hand or library"), but replacements
are synchronous and cannot ask a player. The engine instead lets the move happen and, before
anyone gets priority, offers the move to the command zone (the same decision as 903.9a). The
visible difference: during the resolution that bounced it, the commander is briefly in the
hand/library. See "Decisions to confirm" in the release notes.

## Slices

1. Format, color identity, deck commander and validation, `Setup` option.
2. Command zone, casting from it, tax.
3. 903.9 decision, 21-damage state-based action.
4. Snapshot, view, `DeckBuilder`, CLI.
5. Fuzz, rules monitor, docs, 0.3.0 release.

## Snapshot compatibility

New keys (`format`, `commanders`, per-player `commander_casts` and `commander_damage`) are
optional with defaults, as every earlier addition was; constructed snapshots are unchanged
and old ones still load. `VERSION` stays 2.
