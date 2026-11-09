# Using Enjine from Ruby

This guide is for code that *calls* Enjine: a game client, a bot, a simulator, a
reinforcement-learning environment, a test harness. It covers everything public:
cards and decks, starting games, the decision loop, what players may see, events,
saving and replaying, the deck builder and the testing tools.

- [1. The model in one minute](#1-the-model-in-one-minute)
- [2. Cards](#2-cards)
- [3. Decks and players](#3-decks-and-players)
- [4. Setups and games](#4-setups-and-games)
- [5. The decision loop](#5-the-decision-loop)
- [6. Decision kinds and options](#6-decision-kinds-and-options)
- [7. Ids and references](#7-ids-and-references)
- [8. Observing a game: views](#8-observing-a-game-views)
- [9. History and events](#9-history-and-events)
- [10. Saving, replaying, branching](#10-saving-replaying-branching)
- [11. Writing a bot or an RL environment](#11-writing-a-bot-or-an-rl-environment)
- [12. The deck builder](#12-the-deck-builder)
- [13. Testing tools: RulesMonitor, Fuzz and Verify](#13-testing-tools-rulesmonitor-fuzz-and-verify)
- [14. The command line](#14-the-command-line)
- [15. Errors](#15-errors)
- [16. Guarantees and limits](#16-guarantees-and-limits)

```ruby
# Gemfile
gem "enjine", git: "https://github.com/thisiscetin/enjine"
```

```ruby
require "enjine"                 # the engine
require "enjine/deck_builder"    # optional: random decks from a card pool
```

Ruby 4.0, no runtime dependencies.

## 1. The model in one minute

```ruby
alice = Enjine::Player.new(name: "alice", deck: alice_deck)   # a deck document (Hash), see §3
bob   = Enjine::Player.new(name: "bob",   deck: bob_deck)
setup = Enjine::Setup.new(alice, bob)    # validate and compile once
game  = setup.new_game(seed: 42)         # cheap: make as many as you like

until game.over?
  decision = game.pending_decision       # who must decide, what kind, every legal option
  game.submit(decision.options.sample)   # answer with one of the options, exactly as given
end

game.result   # => {"winner" => "bob", "reason" => "life"}
```

Four ideas carry the whole API:

1. **The engine never decides for a player.** Every choice the rules give a
   player — keeping a hand, passing priority, each target, each mana payment,
   each attacker — is one *decision* with a complete list of legal *options*.
   There is no auto-pass and no hidden default.
2. **Options are plain hashes.** `{type: "cast", object: "lightning_bolt#12"}`.
   You never construct actions; you pick one from the list. Anything not in the
   list raises `Enjine::IllegalDecision` and leaves the game untouched.
3. **Deterministic.** All randomness (shuffles, die rolls, random choices) comes
   from the game's seeded RNG. Same cards, same seed, same decisions → the same
   game, bit for bit.
4. **Everything is data.** Cards, decks, decisions, views, events and saved games
   are JSON-compatible hashes.

## 2. Cards

Enjine ships no cards and never reads card text. Every card is a JSON object
written in the card DSL, describing what the card *does*:

```json
{ "name": "Lightning Bolt", "mana_cost": "{R}", "types": ["instant"],
  "abilities": [ { "spell": { "targets": ["any_target"],
    "effects": [ { "deal_damage": { "amount": 3, "to": { "target": 0 } } } ] } } ],
  "rarity": "common", "printing": { "set": "fdn", "number": "1" } }
```

`rarity` and `printing` are optional and ignored by the rules. The full language
(fields, abilities, effects, filters, costs, multi-face cards, keywords) is in
the [card DSL guide](card-data-format.md); the exhaustive list of primitives is
generated in [docs/reference/](../reference).

Validate a card without starting a game:

```ruby
definition = Enjine::CardDefinition.from_h(card_hash)   # frozen, validated
definition.id     # => "lightning_bolt"   (slug of the name; the card's id everywhere)
definition.name   # => "Lightning Bolt"
definition.to_h   # => the card data, round-trippable
```

A bad card raises `Enjine::InvalidCardDefinition`; `#errors` lists every problem
with its path:

```ruby
rescue Enjine::InvalidCardDefinition => e
  e.errors
  # => ["abilities[0].spell.effects[0].deal_damage.to: required",
  #     "toughness: creatures need an integer toughness (CR 302.4)", ...]
```

A `Catalog` is a set of definitions keyed by id. You rarely build one yourself
(decks and setups do), but it's what `Game.import` needs:

```ruby
catalog = Enjine::Catalog.from_definitions(cards)  # Hashes or CardDefinitions
catalog.fetch("lightning_bolt")                     # by id ...
catalog.fetch("Lightning Bolt")                     # ... or by name
```

Two different cards with the same name raise `Enjine::CatalogConflict`.

## 3. Decks and players

A **deck document** carries the cards it uses, so it is self-contained:

```json
{
  "name": "gruul_beats",
  "description": "optional, free text",
  "cards":   [ { "name": "Forest", "types": ["land"], "supertypes": ["basic"], "subtypes": ["forest"] },
               { "name": "Grizzly Bears", "mana_cost": "{1}{G}", "types": ["creature"], "power": 2, "toughness": 2 } ],
  "main":    [ { "card": "Forest", "count": 24 }, { "card": "Grizzly Bears", "count": 2 }, "..." ],
  "outside": [ { "card": "Grizzly Bears", "count": 2 } ]
}
```

- `cards`: card data blocks (§2). `main` and `outside` refer to them by name or id.
- `main`: the decklist. Constructed rules apply (CR 100.2a): at least 60 cards,
  at most 4 copies of a card unless it is a basic land or says otherwise
  (`"deck_limit"` in the card data).
- `outside` (optional): cards the player owns outside the game — the sideboard
  that "from outside the game" effects use (CR 400.11). At most 15 (CR 100.4a);
  the copy limit counts both lists.

```ruby
player = Enjine::Player.new(name: "alice", deck: doc)   # doc: Hash or Enjine::Deck
player.ready?          # => true when the deck is legal
player.deck.errors     # => ["deck has 10 cards; at least 60 are required (CR 100.2a)", ...]
player.deck.size       # => 60
player.deck.entries    # => {"forest" => 24, "grizzly_bears" => 4, ...}
```

An illegal deck can still be built and inspected; it just isn't `ready?`, and
`Setup.new` refuses it with `Enjine::PlayerNotReady` (whose `#errors` are the
deck's). A malformed document (not a Hash, `main` not a list, unknown card
reference) raises `Enjine::InvalidDeck`.

While a player is seated in an unfinished game, editing their deck raises
`Enjine::DeckLocked`.

## 4. Setups and games

```ruby
setup = Enjine::Setup.new(alice, bob)
```

A `Setup` is a frozen, compiled pairing of two ready players: their cards are
validated and merged into one catalog once. Player names must differ. Spawning
games from it is cheap, so keep one `Setup` per matchup and create games from it:

```ruby
game = setup.new_game(seed: 42)   # Integer seed; drives every random event of the game
```

The game starts at its very first decision: the die-roll winner chooses to play
or draw (CR 103.1), then each player decides on a mulligan.

| `Game` method | Returns |
| --- | --- |
| `pending_decision` | the `Decision` the engine waits for, or `nil` when the game is over |
| `legal_options` | `pending_decision.options` (or `[]`) |
| `submit(option)` | applies one option, returns the `HistoryEntry` it produced |
| `apply([options])` | submits several, all or nothing; returns the game |
| `concede(player)` | the player concedes (CR 104.3a), at any time |
| `over?`, `result` | `result` is `{"winner" => name or nil, "reason" => "..."}` once over |
| `turn`, `step`, `names` | turn number, current step as a Symbol (`:precombat_main`), the two names |
| `view_for(viewer)` | what a player (by name) or `:observer` may see (§8) |
| `history`, `history_for(viewer)`, `decision_log` | everything that happened (§9) |
| `subscribe { \|event\| }` | live typed events (§9) |
| `export`, `to_h` | a JSON snapshot / its Hash (§10) |
| `fork` | an independent copy for search and lookahead (§10) |
| `restart(seed: nil)` | back to the opening, same or new seed |
| `catalog` | the cards of this game |

`result["reason"]` is why the loser lost: `life` (CR 704.5a), `empty_library`
(drew from an empty library, 704.5b), `poison` (704.5c), `concede` (104.3a),
`effect` ("you lose the game") or `opponent_won` ("you win the game"). When both
players lose at once the game is a draw: `"winner" => nil` and the reasons are
joined, e.g. `"life,life"` (CR 104.4a).

## 5. The decision loop

```ruby
decision = game.pending_decision
decision.player    # => "alice"          who must decide
decision.kind      # => "choose_target"  what kind of decision (§6)
decision.options   # => [{type: "target", target: "player:bob"}, {type: "cancel"}, ...]
decision.details   # => {"index" => 0}   extra context for this kind
decision.to_h      # => {"player" => ..., "kind" => ..., "options" => [...], "index" => 0}
```

Real examples (`decision.to_h`, from an actual game):

```json
{"player":"alice","kind":"play_or_draw","options":[{"type":"play"},{"type":"draw"}]}
{"player":"bob","kind":"mulligan","options":[{"type":"keep"},{"type":"mulligan"}]}
{"player":"alice","kind":"choose_target","index":0,
 "options":[{"type":"target","target":"player:alice"},{"type":"target","target":"player:bob"},{"type":"cancel"}]}
{"player":"alice","kind":"pay_cost","remaining":"{R}",
 "options":[{"type":"activate_mana","object":"mountain#137","ability":"intrinsic:mountain"},{"type":"cancel"}]}
{"player":"bob","kind":"declare_attackers",
 "options":[{"type":"done"},{"type":"attack","object":"horned_turtle#149","target":"player:alice"}]}
```

**Submitting.** Pass one of the options back. Symbol or string keys both work, so
options that went through JSON can be submitted as they are:

```ruby
game.submit(decision.options.first)
game.submit({"type" => "pass"})           # same as {type: "pass"}
```

An option that isn't legal raises `Enjine::IllegalDecision` (`#option`,
`#legal_options`) and changes nothing. Submitting after the game ended raises too.

**Priority.** Most decisions are `priority`: the player holding priority picks an
action (`play_land`, `cast`, `activate`, `activate_mana`) or `{type: "pass"}`.
When both players pass in succession with an empty stack, the step ends; with
something on the stack, its top resolves (CR 117.4). The engine never passes
for anyone: a client that wants auto-pass submits `pass` itself when it is the
only option (the CLI does this for human seats).

### Casting is several small decisions

Casting a spell (CR 601.2) is a short conversation, each step its own decision.
Lightning Bolt with a Mountain in play:

```ruby
game.submit(type: "cast", object: "lightning_bolt#12")      # priority: the card moves to the stack
game.submit(type: "target", target: "player:bob")           # choose_target
game.submit(type: "activate_mana", object: "mountain#3",
            ability: "intrinsic:mountain")                  # pay_cost: tap the Mountain, {R} in pool
game.submit(type: "pay_mana", mana: "R")                    # pay_cost: spend it -> the spell is cast
```

Depending on the card, the engine also asks for modes (`choose_mode`), X
(`choose_x`), kicker (`choose_kicker`), the number of targets
(`choose_target_count`), how to divide damage (`distribute`), or which permanent
pays a cost (`choose_cost`). Abilities (`activate`) work the same way.

**Cancelling.** Until the last payment, `{type: "cancel"}` is offered and rewinds
the whole cast: the card returns to its place in hand, sources tapped for it
untap and the mana pool is restored (CR 734). It stops being offered once
something irreversible is paid (a Treasure was sacrificed for mana).

### Combat

`declare_attackers` and `declare_blockers` collect one creature at a time:
`{type: "attack", object:, target:}` / `{type: "block", object:, attacker:}`,
then `{type: "done"}`. `done` is only offered when the declaration is legal
(menace, "attacks each combat if able", "can't attack alone"); `withdraw` /
`unblock` undo a pick. When a blocked creature's damage has to be split,
`assign_damage` asks one point at a time.

## 6. Decision kinds and options

| Kind | When | Options |
| --- | --- | --- |
| `play_or_draw` | die-roll winner, game start | `play`, `draw` |
| `mulligan` | each player, in turn order | `keep`, `mulligan` (London) |
| `bottom` | after a mulligan | `{type: "bottom", object:}` once per mulligan |
| `priority` | most of the game | `pass`, `play_land`, `cast`, `activate`, `activate_mana` |
| `choose_mode` | modal spell or ability | `{type: "mode", mode: i}`, `done`, `cancel` |
| `choose_x` | {X} in a cost | `{type: "x", value: n}`, `cancel` |
| `choose_kicker` | spell with kicker | `kick`, `no_kick`, `cancel` |
| `choose_target_count` | "X target ...", "any number of target ..." | `{type: "count", count: n}`, `cancel` |
| `choose_target` | each target | `{type: "target", target: ref}`, `done` (for "up to"), `cancel` |
| `distribute` | dividing damage/counters | `{type: "assign", target: ref}`, `cancel` |
| `choose_cost` | a cost that picks permanents/cards (sacrifice, crew, station, ...) | `{type: "cost", object:}`, `done`, `cancel` |
| `pay_cost` | paying mana | `activate_mana`, `pay_mana`, `convoke`, `cancel` |
| `order_triggers` | several of your triggers at once | `{type: "trigger", trigger: id}` |
| `effect_choice` | a choice while something resolves (scry, surveil, "you may", choose a card, ...) | one of the listed `choices`; `prompt` describes it |
| `enter_choice` | as a permanent enters ("choose a color", "pay 2 life or enters tapped") | `color`, `creature_type`, `number`, `name`, `option`, `pay_life`, `enter_tapped`, ... |
| `untap_choice` | "you may choose not to untap" | `untap`, `keep_tapped` |
| `legend_rule` | two legends with one name | `{type: "keep", object:}` |
| `declare_attackers` | your combat | `attack`, `withdraw`, `done` |
| `declare_blockers` | opponent's combat | `block`, `unblock`, `done` |
| `assign_damage` | splitting combat damage | `{type: "assign", object:}` |
| `discard` | cleanup, over 7 cards | `{type: "discard", object:}` |

The generated [decision reference](../reference/decisions.md) documents every
kind's options and `details` exactly. Treat the option list as the source of
truth: new mechanics add kinds and option types, and a client that renders or
picks from `options` generically keeps working.

## 7. Ids and references

| Thing | Form | Example |
| --- | --- | --- |
| card definition | slug of its name | `"lightning_bolt"` |
| game object (card or token in a zone, spell, ability on the stack) | `"<card id>#<n>"` | `"lightning_bolt#12"` |
| player | name, or `"player:<name>"` where a target is expected | `"alice"`, `"player:alice"` |
| ability of an object | ref string | `"printed:0"`, `"intrinsic:mountain"`, `"keyword:station"`, `"granted:<card>:printed:0:0"` |
| card outside the game | `"outside:<card id>"` | `"outside:negate"` |

An object's id lasts while it stays in one zone. Moving zones makes a new object
with a new id (CR 400.7); the `zone_changed` event carries `old_id` and `new_id`,
so you can follow a card.

## 8. Observing a game: views

```ruby
game.view_for("alice")     # what alice may know
game.view_for(:observer)   # everything (both hands, library order)
```

A view is a plain Hash:

```ruby
{
  "viewer" => "alice", "turn" => 7, "active" => "bob", "step" => "declare_attackers",
  "phase" => "combat", "priority" => "bob",
  "players" => [ ...one per player... ],
  "battlefield" => [ ...objects... ], "stack" => [...], "exile" => [...], "phased_out" => [...],
  "pending" => { ...the pending decision, as this viewer may see it... },
  "result" => nil,
  "effects" => [ ...continuous effects in force (pumps, grants, control changes)... ],
  "delayed_triggers" => [ ...waiting delayed triggers... ]
}
```

A player entry:

```json
{"name":"alice","life":18,"poison":0,"mana_pool":{"R":1},"restricted_mana":[],"lands_played":1,
 "mulligans":0,"hand_count":6,"library_count":43,"outside_count":0,"graveyard":[ ... ],
 "hand":[ ... ], "outside":[ ... ]}
```

`hand` and `outside` appear only for their owner (and the observer); `library`
(in order, top first) only for the observer; `speed` once the player has one.

A permanent shows its **current** characteristics, after counters and continuous
effects — what the rules use, not what's printed:

```json
{"id":"savannah_lions#187","card":"savannah_lions","name":"Savannah Lions","type_line":"Creature — Cat",
 "owner":"bob","controller":"bob","mana_cost":"{W}","keywords":["double_strike"],"tapped":true,
 "power":3,"toughness":2,"damage":0,"summoning_sick":false,"counters":{"+1/+1":1},
 "attacking":"player:alice"}
```

Other keys appear when they apply: `loyalty`, `blocking`, `attached_to`,
`transformed`, `prepared`. Face-down exiled cards show only `{"face_down": true}`
to players who may not look at them (CR 406.3).

## 9. History and events

Every `submit` returns a `HistoryEntry`: the decision and every event it caused.

```json
{"seq":33,"turn":2,"step":"declare_attackers","player":"alice","kind":"pay_cost",
 "option":{"type":"pay_mana","mana":"R"},
 "events":[{"type":"mana_paid","player":"alice","mana":"{R}","object":"lightning_bolt#138"},
           {"type":"spell_cast","player":"alice","object":"lightning_bolt#138","card":"lightning_bolt",
            "targets":["player:bob"],"during_resolution":false}]}
```

```ruby
game.history                 # all HistoryEntry objects (entry.to_h = observer form)
game.history_for("bob")      # Hashes, hidden information redacted for bob
game.subscribe { |event| }   # called with each typed event as it happens
```

Redaction follows the rules on hidden information: bob doesn't learn which card
alice drew or put on the bottom, but he does see that she drew one, and every
public move in full.

**Events** are `Data` objects (`event.type`, `event.to_h`, `event.for_viewer(name)`),
all listed in `Enjine::Events::REGISTRY`. The common ones:

| Event | Fields |
| --- | --- |
| `game_started`, `die_rolled`, `starting_player_chosen` | `players`, `seed` / `winner` / `chooser`, `choice`, `starting_player` |
| `mulligan_declared`, `mulligan_taken`, `hand_kept` | `player`, `choice` / `mulligans` |
| `turn_began`, `step_began` | `turn`, `active` / `turn`, `step`, `phase` |
| `priority_passed` | `player` |
| `zone_changed` | `card`, `old_id`, `new_id`, `owner`, `from`, `to`, `reason` (`draw`, `play_land`, `cast`, `resolve`, `destroy`, `sacrifice`, `countered`, `sba_lethal_damage`, ...) |
| `spell_cast`, `ability_activated`, `cast_cancelled`, `resolved`, `fizzled` | `player`, `object`, `card`, `targets`, ... |
| `ability_triggered`, `trigger_put_on_stack` | `player`, `source`, `card`, `ability` |
| `tapped`, `untapped`, `mana_added`, `mana_paid`, `mana_emptied` | `object` / `player`, `mana` |
| `attacker_declared`, `blocker_declared`, `became_blocked`, `damage_assigned` | `object`, `target` / `attacker` / `blockers` |
| `damage_dealt` | `source`, `target`, `amount`, `combat` |
| `life_changed` | `player`, `from`, `to` |
| `counters_changed` | `object`, `counter`, `from`, `to` |
| `effect_started`, `effects_ended` | `kind`, `affected`, `details` / `count` |
| `control_changed`, `attached`, `transformed`, ... | mechanic-specific |
| `player_lost`, `game_ended` | `player`, `reason` / `winner`, `reason` |

## 10. Saving, replaying, branching

```ruby
json = game.export                          # any moment, even halfway through a cast
game = setup.import(json)                   # or Enjine::Game.import(json, catalog: setup.catalog)
```

The snapshot holds the full state and history. Import checks it for
consistency and raises `Enjine::InvalidSnapshot` (with `#errors`) if it's
malformed. A snapshot needs the same cards (`catalog`) to load.

**Replay.** The seed plus the decision log reproduces a game exactly:

```ruby
log    = game.decision_log                       # every submitted option
replay = setup.new_game(seed: 42).apply(log)     # identical game
replay.export == game.export                     # => true
```

`apply` is all or nothing: if option *i* is illegal it raises
`IllegalDecision` with `#index == i` and the game is unchanged.

**Branching.** `game.fork` returns an independent copy (state and history; not
subscribers). It's the tool for search: fork, try a line, look at the result,
throw it away. A fork takes well under a millisecond on a mid-game board.

```ruby
best = game.legal_options.max_by do |option|
  trial = game.fork
  trial.submit(option)
  evaluate(trial.view_for(game.pending_decision.player))
end
```

`game.restart(seed:)` resets to the opening with the same decks.

## 11. Writing a bot or an RL environment

An agent is anything that turns a `Decision` into one of its options:

```ruby
class MyAgent
  def choose(decision) = decision.options.first   # your policy here
end

agents = { "alice" => MyAgent.new, "bob" => Enjine::Agents::Random.new(seed: 7) }
game = setup.new_game(seed: 1)
game.submit(agents.fetch(game.pending_decision.player).choose(game.pending_decision)) until game.over?
```

`Enjine::Agents::Random.new(seed:, cancel_rate: 0.02)` picks uniformly (rarely
cancelling a cast), and is the baseline opponent.

For reinforcement learning:

- **Action space**: the current decision's `options`. They are already the
  legal-action mask; encode them (e.g. by `type` + referenced object features)
  and choose among them. Small decisions keep the branching factor low: a cast
  is several picks rather than one huge combined action.
- **Observation**: `view_for(player)` gives exactly the information that player
  is entitled to (no peeking at hands or library order). `view_for(:observer)` is
  there for privileged critics or debugging.
- **Reward**: `game.result` when `over?`; intermediate signals from events
  (`life_changed`, `zone_changed` with reason `sba_lethal_damage`, ...) via
  `subscribe` or the returned history entries.
- **Episodes**: compile the `Setup` once per matchup; `new_game(seed:)` per
  episode. Seeds make every episode reproducible.
- **Throughput**: about 4,000 decisions per second single-threaded with the
  random agent on the example decks (`bundle exec rake bench` measures it on
  your machine). Games share nothing mutable, so parallel rollouts can run one
  game per process (or per thread).

## 12. The deck builder

`require "enjine/deck_builder"`. One builder holds a card pool and builds as many
random, legal, plausibly shaped decks from it as you ask. It knows nothing about
sets: the pool is whatever cards you give it.

```ruby
builder = Enjine::DeckBuilder.new(cards)              # Array of card Hashes / CardDefinitions
deck = builder.build(colors: %w[W U], seed: 7)        # chosen colors
deck = builder.build(colors: 2, seed: 8)              # two random colors
deck = builder.build(seed: 9, size: 80)               # :any colors (1, 2 or 3, weighted)
deck = builder.build(seed: 10, profile: { lands: { range: 16..18, center: 17, outliers: 16..18 } })
player = Enjine::Player.new(name: "bob", deck: deck)
```

- A pool entry may be `{"card" => card, "count" => n}`: you own n copies, so no
  deck holds more (a personal collection).
- Each count (lands 22–26, creatures 14–24, the rest other spells; mana curve;
  copies per card; nonbasic lands; color balance) is drawn from a range, with
  occasional outliers; all of them can be overridden with `profile:` (see
  `DeckBuilder::DEFAULT_PROFILE`). Counts scale with `size:`.
- Only cards the chosen colors can cast are used; basic lands always exist.
- Same pool + arguments + seed → same deck, whatever order the pool is in.
- `build` returns a deck document with a `description` like
  `"random deck: colors=WG seed=3 — 23 lands, 25 creatures, 12 other spells, 14 distinct cards"`.
- If the pool can't fill the deck: `DeckBuilder::NotEnoughCards`, with a message
  and `#details` (`{pool:, colors:, creatures_available:, missing:, ...}`).

More in the [deck builder guide](deck-builder.md).

## 13. Testing tools: RulesMonitor, Fuzz and Verify

`Enjine::RulesMonitor` is an independent rules checker: it re-derives from raw
state and events what must be true after each decision (life totals, mana
emptying, lethal damage, summoning sickness, land plays, P/T, ...), without using
the engine's rules code.

```ruby
monitor = Enjine::RulesMonitor.new(game)
monitor.check!(game.submit(option))   # after every submit
monitor.findings   # => [] or [Finding(rule: "704.5g", message:, turn:, step:, seq:)]
monitor.stats      # mechanics seen, e.g. {"spell_cast" => 12, "damage_dealt" => 30}
```

`Enjine::Fuzz` plays random games with invariant checks, the monitor and
export/import round-trips, and raises `Fuzz::Failure` (with `seed` and
`decisions`) on any problem:

```ruby
result = Enjine::Fuzz.run(setup, games: 50, seed: 1, roundtrip_every: 25)
result.games; result.decisions; result.outcomes; result.casts; result.seconds
Enjine::Fuzz.random_deck(cards, rng: Enjine::Rng.from_seed(3))   # a random legal deck, any colors
```

Use them when you write your own cards: a game that breaks names the seed to
reproduce it.

`Enjine::Verify` (`require "enjine/verify"`) does all of this for a folder of
card files at once. It reads every `.json` file below the folder (each holds one
card or an array of cards), validates every card, builds decks from the valid
ones so that every card is in some deck, and plays games watched by the rules
monitor. It records which cards were actually used (cast, played, activated,
triggered or resolved), and gives cards that were never used extra decks of their
own:

```ruby
require "enjine/verify"
report = Enjine::Verify.new("my_cards/", games: 20, seed: 1).run
report["ok"]           # false if any card is invalid, the monitor found a rules error, or the engine raised
report["invalid"]      # [{"file", "index", "name", "errors" => ["types[0]: unknown type ..."]}]
report["unexercised"]  # valid cards no game ever used: write a scenario for them
report["findings"]     # rules-monitor findings, with the seed and both deck descriptions
report["types"]        # per card type: total / valid / exercised
puts Enjine::Verify.text(report)
```

The same folder, `games` and `seed` give the same report. Two cards with the same
name but different rules data count as invalid; an identical reprint counts once.

## 14. The command line

```sh
exe/enjine --deck1 a.json --deck2 b.json                 # hot-seat: you play both sides
exe/enjine --deck1 a.json --deck2 b.json --p2 random     # against the random agent
exe/enjine --deck1 a.json --deck2 b.json --p1 random --p2 random --seed 7 [--quiet] [--observer]
exe/enjine --pool cards.json --deck1 random:colors=RG --deck2 random   # random decks from a pool
exe/enjine --pool cards.json --random-deck colors=WU seed=7            # print a random deck document
exe/enjine --validate cards.json                         # JSON report; exit 1 if any card is invalid
exe/enjine --verify my_cards/ [--games N] [--seed S] [--json]  # validate and play-test a folder of cards
exe/enjine --load game.json                              # resume a game saved with `s`
```

In a game: a human seat whose only option is to pass priority passes
automatically. A number picks an option, `b` shows the board, `o` toggles the observer view, `h [n]` shows history, `u` undoes,
`s FILE` saves, `c` concedes, `q` quits, `?` helps.

## 15. Errors

All inherit from `Enjine::Error`.

| Error | Raised by | Carries |
| --- | --- | --- |
| `IllegalDecision` | `submit`, `apply`, `concede` | `option`, `legal_options`, `index` (for `apply`) |
| `InvalidCardDefinition` | `CardDefinition.from_h`, decks, catalogs | `errors` (path-addressed) |
| `InvalidDeck` | `Player.new` / `Deck.from_h` on a malformed document | `errors` |
| `PlayerNotReady` | `Setup.new` with an illegal deck | `errors` |
| `InvalidSnapshot` | `Game.import` / `Setup#import` | `errors` |
| `CatalogConflict` | two different cards with the same id | message |
| `DeckLocked` | editing a deck while its player is in a game | message |
| `DeckBuilder::NotEnoughCards` | `DeckBuilder#build` | `details` |
| `Fuzz::Failure` | `Fuzz.run` | `seed`, `decisions` |

A failed call never changes a game: `submit` and `apply` validate first, and
`apply`/`import` are all or nothing.

## 16. Guarantees and limits

- **Rules**: two-player games by the Comprehensive Rules pinned in
  `Enjine::RULES_VERSION` (2026-11-06). Code and tests cite rule numbers.
- **Stable surface**: everything in this guide. `game.state` and the engine's
  internals are for tests and debugging and may change.
- **Determinism**: the RNG is a seeded PCG32 (`Enjine::Rng`); nothing reads the
  clock or global randomness.
- **Threading**: a game is not thread-safe; use one game per thread. Games and
  setups share only frozen data.
- **Not included**: matches (best of three), sideboarding between games,
  multiplayer, and any card data. Cards you write are validated: a mechanic the
  engine doesn't have is rejected with an error naming the unknown key and
  listing the supported ones (`abilities[0].spell.effects[0]: unknown effect
  "teleport" (supported: add_counters, ...)`).
