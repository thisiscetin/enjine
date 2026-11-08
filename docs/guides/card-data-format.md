# Card data format — a guide for conversion agents

This guide is written for an agent (or a person) whose job is:

1. **pull** cards from a card database (Scryfall, MTGJSON, your own DB),
2. **convert** each card into Enjine's card data format,
3. **validate** it with Enjine,
4. **push** the valid result to a database, and report what could not be converted.

Enjine has no built-in card list. A card exists only as a *data block* (JSON) that
Enjine validates and compiles. If a card uses a mechanic Enjine does not support
yet, validation **fails with a precise error**. That is expected: store the card
as *unsupported*, record the errors, and move on. Never approximate a card. A
wrong card is worse than a missing one.

**Source of truth for what is supported:** [`SUPPORTED.md`](../../SUPPORTED.md) and
[`docs/reference/`](../reference). These files are generated from the code, so a
primitive listed there works, and a primitive not listed there does not exist yet.

---

## 1. The workflow

```
for each card in source DB:
    data   = convert(card)                 # this guide, sections 2-6
    report = enjine --validate data.json   # section 7
    if valid:   upsert(cards_table, report.valid[i].card)      # canonical form
    else:       upsert(unsupported_table, card.name, report.invalid[i].errors)
```

Rules for the agent:

- **Convert from the oracle text, not the printed text.** Use Scryfall's
  `oracle_text` and `type_line`, or MTGJSON's `text`. Oracle text is the up-to-date
  wording that the rules use.
- **One card, one block.** For multi-face cards (split, adventure, MDFC,
  transform), *skip the card for now* and record `"unsupported": "multi-face"`.
  Enjine doesn't model faces yet.
- **Never invent mechanics.** If any part of the oracle text can't be expressed
  with the primitives in `SUPPORTED.md`, the card is unsupported. Don't drop that
  part, and don't "close enough" it.
- **Store the canonical form.** Store `report.valid[i].card` (the output of
  `CardDefinition#to_h`), not your input. It is normalized: mana costs are
  re-rendered and empty fields are dropped.
- **Record the printing, not a vendor id.** Store the set code and collector
  number printed on the card (`trk`, `12`). Any card source resolves them
  (Scryfall `/cards/trk/12`, MTGJSON set + `number`), so images and prices stay
  one lookup away without tying your data to a single provider.
- **Version your rows.** Store `rules_version` and `engine_version` from the
  report next to each card. When Enjine gains a mechanic, re-run the unsupported
  table, not the whole database.
- **Prioritize Standard-legal cards.** Mechanics that only appear on cards that
  have left Standard are low priority.

---

## 2. Top-level fields

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `name` | yes | string | Unique. Its slug becomes the card id: `"Jace, the Mind Sculptor"` → `jace_the_mind_sculptor`. Two different definitions with the same name in one game raise `CatalogConflict`. |
| `types` | yes | list | Card types, lowercase: `land`, `creature`, `artifact`, `enchantment`, `planeswalker`, `instant`, `sorcery`. A card can have several (`["artifact", "creature"]`). |
| `mana_cost` | castable cards | string | `"{2}{W}{W}"`. Symbols: `{N}` generic, `{W}{U}{B}{R}{G}`, `{C}`. Lands must **not** have one. A card without one can't be cast. Hybrid, Phyrexian, `{X}` and `{S}` are not supported yet. |
| `supertypes` | no | list | `basic` (exempt from the 4-copy rule). `legendary` and `snow`: not yet. |
| `subtypes` | no | list | Lowercase, spaces become `_`: `["human", "wizard"]`. Free-form labels, except the basic land types `plains island swamp mountain forest`, which grant their mana ability automatically (CR 305.6) and are valid only on lands. |
| `keywords` | no | list | Keyword abilities, lowercase: see `SUPPORTED.md` → *Keyword abilities*. |
| `power`, `toughness` | creatures | integer | Required for creatures; not allowed on other types. `*` values are not supported yet. |
| `loyalty` | planeswalkers | integer | Starting loyalty. |
| `abilities` | no | list | Section 4. |
| `rules_text` | no | string | Informational only (shown in the CLI). Put the oracle text here. |

Any other field is an error. That's deliberate: a typo must never be silently ignored.

### Mapping a Scryfall object

| Scryfall | Enjine |
| --- | --- |
| `name` | `name` |
| `mana_cost` (`"{1}{G}"`) | `mana_cost` (omit for lands, and when Scryfall's value is `""`) |
| `type_line` `"Legendary Creature — Elf Druid"` | split on `—`. Left side: words in `{legendary, basic, snow, world}` → `supertypes`, the other words → `types` (lowercased). Right side → `subtypes` (lowercased, spaces → `_`). |
| `power` / `toughness` / `loyalty` (strings) | integers. Any `*` or `X` → unsupported. |
| `keywords` (`["Flying", "Haste"]`) | `keywords`, lowercased. **Check every one against SUPPORTED.md.** |
| `oracle_text` | `rules_text` (verbatim), and the source of `abilities` |
| `card_faces` present | unsupported (`multi-face`) |
| `layout` not `normal` | unsupported for now (`layout: <value>`) |

Watch out: Scryfall's `keywords` array includes **keyword actions** too (e.g.
`"Scry"`, `"Mill"`), and those are not `keywords` in Enjine. Only keyword
*abilities* (rule 702) go in `keywords`. Keyword actions are effects inside an
ability.

---

## 3. Mana abilities of lands

Basic land types give their ability automatically, so don't write it:

```json
{ "name": "Forest", "types": ["land"], "supertypes": ["basic"], "subtypes": ["forest"] }
```

Any other mana ability is written explicitly:

```json
{ "name": "Wastes", "types": ["land"], "supertypes": ["basic"],
  "abilities": [{ "mana": { "cost": ["tap"], "produce": "{C}" } }] }
```

`produce` is a string of mana symbols: `"{G}"`, `"{C}{C}"`. "Add one mana of any
color" and other choices are not supported yet.

---

## 4. Abilities

`abilities` is a list. Each entry is an object with **one key**: the ability kind.

| Kind | Where | Oracle text shape |
| --- | --- | --- |
| `spell` | instants, sorceries | the whole text of the spell |
| `activated` | permanents | `"[Cost]: [Effect]."` |
| `loyalty` | planeswalkers | `"+1: …"`, `"−2: …"` |
| `mana` | permanents | `"{T}: Add {G}."` |

### 4.1 Spell ability (instants and sorceries)

```json
{ "spell": {
    "targets": ["any_target"],
    "effects": [{ "deal_damage": { "amount": 3, "to": { "target": 0 } } }] } }
```

- `targets`: one target filter per "target" word in the oracle text, **in order of
  appearance**. The text "deals 2 damage to target creature and 2 damage to target
  player" has two targets: `["creature", "player"]`.
- `effects`: in the order the oracle text lists them. They resolve in that order (CR 608.2c).
- A spell with targets doesn't resolve if *all* its targets are illegal on
  resolution. If some are illegal, only those are skipped.

### 4.2 Activated ability

```json
{ "activated": {
    "cost": ["tap", { "mana": "{1}{R}" }],
    "targets": ["any_target"],
    "effects": [{ "deal_damage": { "amount": 1, "to": { "target": 0 } } }],
    "timing": "instant" } }
```

- `cost`: costs before the colon. `"tap"` is `{T}`; `{ "mana": "{1}{R}" }` is a mana
  cost. Other costs (sacrifice, discard, pay life, `{Q}`) are not supported yet.
- `timing`: `"sorcery"` if the text says "Activate only as a sorcery"; otherwise omit.

### 4.3 Loyalty ability

```json
{ "loyalty": { "cost": -3, "targets": ["creature"],
               "effects": [{ "deal_damage": { "amount": 3, "to": { "target": 0 } } }] } }
```

`cost` is the signed number: `+1` → `1`, `−2` → `-2`, `0` → `0`. Sorcery timing and
once-per-turn are automatic.

### 4.4 Target filters

`any_target` (creature, player or planeswalker), `creature`, `planeswalker`,
`creature_or_planeswalker`, `permanent`, `player`, `opponent`, `spell`. See
`docs/reference/filters.md`. Qualified targets ("target creature *you control*",
"target *nonland* permanent", "target creature with flying") are not supported
yet, so the card is unsupported.

### 4.5 Who an effect applies to: the `to` selector

| Selector | Oracle words |
| --- | --- |
| `{ "target": 0 }` | "target …" (the 1st declared target; `1` is the 2nd, …) |
| `"you"` | "you" ("you gain 3 life", "draw a card") |
| `"each_opponent"` | "each opponent" |
| `"self"` | "this creature" / the card's own name, on a permanent |
| `{ "each": "creature", "controller": "you" }` | "creatures you control", "each creature you control" |
| `{ "each": "creature", "controller": "opponent" }` | "creatures your opponents control" |
| `{ "each": "creature" }` | "each creature", "all creatures" |

### 4.6 Effects

See `docs/reference/effects.md` for the generated list. Currently:

| Effect | Oracle text | Data |
| --- | --- | --- |
| `deal_damage` | "deals N damage to …" | `{ "deal_damage": { "amount": N, "to": … } }` |
| `pump` | "gets +X/+Y until end of turn" | `{ "pump": { "power": X, "toughness": Y, "to": … } }` |
| `add_counters` | "put N +1/+1 counters on …" | `{ "add_counters": { "counter": "+1/+1", "amount": N, "to": … } }` (`+1/+1`, `-1/-1`, `loyalty`) |
| `gain_life` | "you gain N life" | `{ "gain_life": { "amount": N } }` (`to` defaults to `"you"`) |
| `lose_life` | "each opponent loses N life" | `{ "lose_life": { "amount": N, "to": "each_opponent" } }` |
| `draw` | "draw N cards" | `{ "draw": { "amount": N } }` (`to` defaults to `"you"`) |
| `destroy` | "destroy target …" | `{ "destroy": { "to": … } }` |
| `counter` | "counter target spell" | `{ "counter": { "to": { "target": 0 } } }` |

Anything with *conditions* ("if …", "unless …"), *choices* ("choose one —"),
*variable amounts* ("X", "equal to the number of …"), *durations other than until
end of turn*, *triggers* ("when/whenever/at") or *static abilities* ("creatures
you control get +1/+1" with no duration) is **not supported yet**, so the card is
unsupported.

### 4.7 Station cards, Sagas and other set mechanics

Rule numbers are from the 2026-11-06 Comprehensive Rules.

- **Station cards** (CR 702.184, 722). Put `"station"` in `keywords`: that is the
  station activated ability. Each `N+ | …` striation is a `station_symbol` ability.
  The card's power/toughness box goes on the symbol it's printed with (the one the
  reminder text says makes it an artifact creature, else the last one), **not** on the card,
  because a station card has no P/T until it's a creature (CR 722.2c):

  ```json
  { "name": "Example Skiff", "mana_cost": "{2}", "types": ["artifact"], "subtypes": ["spacecraft"],
    "keywords": ["station"],
    "abilities": [{ "station_symbol": { "at": 4, "power": 3, "toughness": 3, "keywords": ["flying"],
                                        "abilities": [] } }] }
  ```

  Abilities printed after the first station symbol belong to its striation: list
  them in that symbol's `abilities`.
- **Sagas** (CR 715). `"subtypes": ["saga"]` on an enchantment, and one `chapter`
  ability per chapter number. "I, II — effect" is two chapter abilities (CR 715.2c):

  ```json
  { "chapter": { "chapter": 1, "targets": ["creature"],
                 "effects": [{ "deal_damage": { "amount": 2, "to": { "target": 0 } } }] } }
  ```

  The lore counters, the precombat-main counter and the sacrifice are automatic.
- **Face a dilemma** (CR 700.17): the trigger `{ "faces_dilemma": {} }` ("whenever
  you face a dilemma"; `"controller": "opponent"` or `"any"` for others).
- **Assimilate** (CR 701.72): the effect `{ "assimilate": { "to": … } }`. "Target
  creature card from a graveyard" is the filter `{ "graveyard_card": { "any_of": ["creature"] } }`.
- **Strange new worlds** is an ability word: drop it. "The number of differently
  named lands you control" is the amount
  `{ "distinct_names": { "each": "land", "controller": "you" } }`.

---

## 5. Worked examples

**Vanilla creature.** "Grizzly Bears {1}{G}, Creature — Bear 2/2":
```json
{ "name": "Grizzly Bears", "mana_cost": "{1}{G}", "types": ["creature"], "subtypes": ["bear"],
  "power": 2, "toughness": 2 }
```

**Keyword creature.** "Raging Goblin {R}, Creature — Goblin Berserker 1/1, Haste":
```json
{ "name": "Raging Goblin", "mana_cost": "{R}", "types": ["creature"], "subtypes": ["goblin", "berserker"],
  "keywords": ["haste"], "power": 1, "toughness": 1, "rules_text": "Haste" }
```

**Instant with two effects.** "Revitalize {1}{W}: You gain 3 life. Draw a card.":
```json
{ "name": "Revitalize", "mana_cost": "{1}{W}", "types": ["instant"],
  "abilities": [{ "spell": { "effects": [{ "gain_life": { "amount": 3 } }, { "draw": { "amount": 1 } }] } }],
  "rules_text": "You gain 3 life. Draw a card." }
```

**Planeswalker.** "+1: Creatures you control get +1/+1 until end of turn. −2: Put a +1/+1 counter on each creature you control.":
```json
{ "name": "Vessa, Rally Captain", "mana_cost": "{2}{W}{W}", "types": ["planeswalker"], "subtypes": ["vessa"],
  "loyalty": 3,
  "abilities": [
    { "loyalty": { "cost": 1, "effects": [
      { "pump": { "power": 1, "toughness": 1, "to": { "each": "creature", "controller": "you" } } }] } },
    { "loyalty": { "cost": -2, "effects": [
      { "add_counters": { "counter": "+1/+1", "amount": 1, "to": { "each": "creature", "controller": "you" } } }] } }
  ] }
```

**Unsupported (correctly rejected).** "Serra Angel, Flying, vigilance":
```json
{ "name": "Serra Angel", "mana_cost": "{3}{W}{W}", "types": ["creature"], "subtypes": ["angel"],
  "keywords": ["flying", "vigilance"], "power": 4, "toughness": 4 }
```
→ `keywords[0]: unknown keyword "flying" (supported: flash, haste)`. Store it as
unsupported, with that error, and convert it again when flying lands.

---

## 6. Decks

A deck document references cards by name (or id) and carries the definitions it uses:

```json
{ "cards": [ { "name": "Forest", ... }, { "name": "Grizzly Bears", ... } ],
  "main":  [ { "card": "Forest", "count": 24 }, { "card": "Grizzly Bears", "count": 4 } ] }
```

A deck is valid with at least 60 cards and at most 4 copies of each non-basic card
(CR 100.2a). `Enjine::Player.new(name:, deck:)` takes this document directly;
`player.ready?` reports validity and `player.deck.errors` explains it.

---

## 7. Validating

From the shell (exit code 0 means all valid, 1 means some invalid):

```sh
bundle exec exe/enjine --validate cards.json
```

`cards.json` is a JSON array of card blocks (or a single block). The report:

```json
{ "rules_version": "2026-09-25", "engine_version": "0.1.0",
  "valid":   [ { "index": 0, "id": "lightning_bolt", "name": "Lightning Bolt", "card": { ...canonical... } } ],
  "invalid": [ { "index": 1, "name": "Serra Angel", "errors": ["keywords[0]: unknown keyword \"flying\" ..."] } ] }
```

From Ruby:

```ruby
require "enjine"

begin
  defn = Enjine::CardDefinition.from_h(data)   # data: Hash parsed from JSON
  store(defn.id, defn.to_h)                    # canonical, round-trips exactly
rescue Enjine::InvalidCardDefinition => e
  store_unsupported(data["name"], e.errors)    # every problem, each with a path
end
```

Error messages always start with a path into your data block
(`abilities[0].spell.effects[1].deal_damage.amount: …`), so an agent can fix the
exact field it got wrong.

## 8. A database schema that works

```sql
CREATE TABLE enjine_cards (
  id              TEXT PRIMARY KEY,      -- CardDefinition#id, e.g. 'lightning_bolt'
  name            TEXT NOT NULL UNIQUE,
  data            JSONB NOT NULL,        -- CardDefinition#to_h (canonical)
  printing_set    TEXT,                  -- set code printed on the card, e.g. 'trk'
  printing_number TEXT,                  -- collector number printed on the card, e.g. '12'
  rules_version   TEXT NOT NULL,         -- report.rules_version
  engine_version  TEXT NOT NULL,         -- report.engine_version
  updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE enjine_unsupported (
  name            TEXT PRIMARY KEY,
  printing_set    TEXT,
  printing_number TEXT,
  errors          JSONB NOT NULL,        -- report.invalid[i].errors
  engine_version  TEXT NOT NULL,
  updated_at      TIMESTAMPTZ DEFAULT now()
);
```

When building a game, load the deck's rows from `enjine_cards` and pass their
`data` as the deck's `cards`.
