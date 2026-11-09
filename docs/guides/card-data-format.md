# The card DSL — writing cards for Enjine

Enjine has no built-in card list and never reads card text. A card exists only as a
**data block** (JSON) that you write by hand in Enjine's card DSL. Enjine validates
it and compiles it. Nothing parses rules text: what a card does is exactly what its
data block says.

```json
{ "name": "Ember Sprite", "mana_cost": "{1}{R}", "types": ["creature"], "subtypes": ["elemental"],
  "keywords": ["haste"], "power": 2, "toughness": 1,
  "abilities": [ { "triggered": { "when": { "enters": {} },
                                  "effects": [ { "deal_damage": { "amount": 1, "to": { "target": 0 } } } ],
                                  "targets": ["any_target"] } } ] }
```

If a block uses something Enjine doesn't support, or has a typo, validation
**fails with a precise error** that names the exact path in your data
(`abilities[0].triggered.effects[0].deal_damage.amount: …`). Nothing is ever
guessed or silently dropped.

**Source of truth for what exists:** [`SUPPORTED.md`](../../SUPPORTED.md) and
[`docs/reference/`](../reference). Both are generated from the code. A primitive
listed there works, and one that isn't listed doesn't exist yet.

---

## 1. Adding a card

1. Write the data block using sections 2–5 (fields, mana abilities, abilities, examples).
2. Validate it: `bundle exec exe/enjine --validate cards.json` (section 7).
3. Put it where you need it:
   - **In a deck document's `cards`** (section 6). This is the simplest option and needs nothing else.
   - **In a card pool** for the [deck builder](deck-builder.md): a JSON array of cards
     (`--pool cards.json`), such as a set or the cards you own.
   - **In your own database** (section 8).

Tips:
- **Store the canonical form.** `CardDefinition#to_h` (the `card` in the validation
  report) is normalized and round-trips exactly.
- **Record the printing, not a vendor id.** The set code and collector number printed on
  the card (`trk`, `12`) can be looked up in any card source.
- **Multi-face cards** (split, adventure, MDFC, transform) aren't modelled yet.

---

## 2. Top-level fields

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `name` | yes | string | Unique (a card with faces: see 4.17). Its slug becomes the card id: `"Jace, the Mind Sculptor"` → `jace_the_mind_sculptor`. Two different definitions with the same name in one game raise `CatalogConflict`. |
| `types` | yes | list | Card types, lowercase: `land`, `creature`, `artifact`, `enchantment`, `planeswalker`, `instant`, `sorcery`. A card can have several (`["artifact", "creature"]`). |
| `mana_cost` | castable cards | string | `"{2}{W}{W}"`. Symbols: `{N}` generic, `{W}{U}{B}{R}{G}`, `{C}`, `{X}` (announced while casting; use the amount `"x"` in effects, see 4.7). Lands must **not** have one. A card without one can't be cast. Two-color hybrid `{R/G}` is supported (paid with either color, CR 107.4e); monocolored hybrid `{2/B}`, Phyrexian and `{S}` are not yet. |
| `supertypes` | no | list | `basic` (exempt from the 4-copy rule). `legendary` and `snow`: not yet. |
| `subtypes` | no | list | Lowercase, spaces become `_`: `["human", "wizard"]`. Free-form labels, except the basic land types `plains island swamp mountain forest`, which grant their mana ability automatically (CR 305.6) and are valid only on lands. |
| `keywords` | no | list | Keyword abilities, lowercase: see `SUPPORTED.md` → *Keyword abilities*. |
| `power`, `toughness` | creatures | integer or amount | Required for creatures; not allowed on other types. A `*` defined by the card ("power is equal to the number of …", CR 604.3) is an amount, see 4.10. |
| `colors` | no | list | `W U B R G`. Only for a color indicator or a token's colors (CR 202.2e, 111.3); otherwise colors come from the mana cost. |
| `loyalty` | planeswalkers | integer | Starting loyalty. |
| `abilities` | no | list | Section 4. |
| `rules_text` | no | string | Informational only (shown in the CLI). Never interpreted. |
| `deck_limit` | no | `"any"` or integer | CR 100.2a exception: "A deck can have any number of cards named ~" is `"deck_limit": "any"`; "up to seven cards named ~" is `7`. Without it a deck may hold four (basic lands: any number). |
| `rarity` | no | string | Catalogue data, e.g. `"rare"`. The rules never read it. |
| `printing` | no | object | `{ "set": "trk", "number": "12" }`: the set code and collector number printed on the card (a number may be given as an integer; it is stored as a string, since numbers like `"12a"` exist). The rules never read it, and two cards differing only in `rarity`/`printing` are the same card (a reprint). On a card with faces it sits beside `faces`. |

Any other field is an error. That's deliberate: a typo must never be silently ignored.

Keyword *actions* such as scry and mill are effects inside an ability, not `keywords`.
Only keyword *abilities* (rule 702) go in `keywords`.

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

`produce` is a string of mana symbols: `"{G}"`, `"{C}{C}"`. When the colors are chosen,
use `color` instead of `produce`, the same shape as the `add_mana` effect (CR 605.3b:
the choice is made as the ability is activated, so each activation option names the
mana it adds, e.g. `{"type": "activate_mana", ..., "mana": "{G}{G}"}`). A mana cost
in a mana ability's `cost` ("{1}, {T}: Add …") is paid from the mana already in your
pool, so tap other sources first:

| Oracle text | Data |
| --- | --- |
| "{T}: Add one mana of any color." | `{ "mana": { "cost": ["tap"], "color": "any_one" } }` |
| "{T}: Add {R} or {G}." | `{ "mana": { "cost": ["tap"], "color": "any_one", "colors": ["R", "G"] } }` |
| "{T}: Add two mana in any combination of {R} and/or {G}." | `{ "mana": { "cost": ["tap"], "color": "any", "amount": 2, "colors": ["R", "G"] } }` |
| "{T}: Add {G} for each creature you control." | `{ "mana": { "cost": ["tap"], "produce": "{G}", "amount": { "count": { "each": "creature", "controller": "you" } } } }` |
| "{T}: Add X mana of any one color, where X is …" | `"color": "any_one", "amount": <amount>` |
| "{T}: Add {C}. Spend this mana only to cast artifact spells or activate abilities of artifacts." | `{ "mana": { "cost": ["tap"], "produce": "{C}", "spend_only": { "spells": { "types": ["artifact"] }, "abilities": { "types": ["artifact"] } } } }` |

```json
{ "name": "Example Lyceum", "types": ["land"],
  "abilities": [{ "mana": { "cost": ["tap", { "mana": "{5}" }], "color": "any_one",
                            "amount": { "distinct_types": { "each": "creature", "controller": "you" } } } }] }
```

**Restricted mana** (CR 106.6): `spend_only` takes `spells` and/or `abilities`, each a
card spec (`"card"` for any spell or source). The mana stays in its own part of the pool
(`restricted_mana` in the view) and is offered as `{"type": "pay_mana", "mana": "C",
"restricted": 0}` only while casting a matching spell or activating an ability of a
matching source; it can't pay a cost asked for while something resolves. `add_mana`
takes `spend_only` too ("Add {C}{C}. Spend this mana only to cast spells.").

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
  cost; `"sacrifice"` sacrifices this permanent; `{ "sacrifice_permanent": { "filter": "creature", "other": true } }`,
  `{ "tap_permanents": { "count": 3, "filter": ... } }` and `{ "remove_counters": { "count": 3 } }` are chosen while
  activating; `"exile_self_from_graveyard"` / `"bottom_self_from_graveyard"` make it a graveyard ability. Pay life
  and `{Q}` are not supported yet.
- `limit: "once_each_turn"`, `only_if: condition`, `timing: "your_turn"`: "Activate only once each turn / only if …
  / only during your turn" (CR 602.5b).
- `timing`: `"sorcery"` if the text says "Activate only as a sorcery"; otherwise omit.

Spells: `{ "kicker": { "cost": [...] } }` (condition `{ "kicked": true }`, spell `kicked_targets`) and
`{ "additional_cost": { "cost": [...] } }`. Targets: `{ "filter": f, "optional": true }` is "up to one target",
`"distinct_from": [0]` keeps a second target of the same word different; `"divide": N` with the effect
`distribute_counters` divides counters among them. "Counter … unless its controller pays {N}" is
`counter_unless_pays`; "you may pay {1}. If you do, …" is `pay`; ward is `{ "ward": { "cost": "{2}" } }`.

**A variable number of targets** (CR 601.2c, 115.3) is one target spec with a `count`: an amount
(`"x"`, a number, or a computed amount) or `"any"`. With `"optional": true` the count is a maximum
("up to"). The player announces how many (decision `choose_target_count`, skipped when the number
is fixed) and then chooses that many different objects; `{ "target": n }` then means each of them.

| Oracle words | Target spec |
| --- | --- |
| "X target creatures" | `{ "filter": "creature", "count": "x" }` |
| "two target creatures" | `{ "filter": "creature", "count": 2 }` |
| "up to X target creatures you control, where X is the number of lands you control" | `{ "filter": { "creature": { "controller": "you" } }, "count": { "count": { "each": "land", "controller": "you" } }, "optional": true }` |
| "any number of target players" | `{ "filter": "player", "count": "any" }` |
| "divided as you choose among any number of target creatures" | `{ "filter": "creature", "count": "any" }` with `"divide": N` (at most N targets; each gets at least one) |

```json
{ "name": "Example Mimic Raid", "mana_cost": "{X}{U}{B}", "types": ["sorcery"],
  "abilities": [{ "spell": {
    "targets": [{ "filter": { "creature": { "controller": "opponent" } }, "count": "x" }],
    "effects": [
      { "create_token_copy": { "of": { "target": 0 }, "except": { "keywords": ["changeling"] } } },
      { "grant": { "keywords": ["haste"], "to": { "result": 0 } } },
      { "delayed_trigger": { "when": { "step_begins": { "step": "end", "whose": "each" } },
                             "effects": [{ "exile": { "to": { "result": 0 } } }] } }] } }] }
```

### 4.3 Loyalty ability

```json
{ "loyalty": { "cost": -3, "targets": ["creature"],
               "effects": [{ "deal_damage": { "amount": 3, "to": { "target": 0 } } }] } }
```

`cost` is the signed number: `+1` → `1`, `−2` → `-2`, `0` → `0`. Sorcery timing and
once-per-turn are automatic.

### 4.4 Target filters

`any_target` (creature, player or planeswalker), `creature`, `planeswalker`,
`creature_or_planeswalker`, `permanent`, `player`, `opponent`, `spell`, `one_of`. See
`docs/reference/filters.md`. A filter takes restrictions as parameters:

| Oracle words | Data |
| --- | --- |
| "you control" / "an opponent controls" | `{ "creature": { "controller": "you" } }` |
| "another" | `{ "creature": { "other": true } }` |
| "nonland", "artifact or creature" | `{ "permanent": { "not": ["land"] } }`, `{ "permanent": { "any_of": ["artifact", "creature"] } }` |
| "artifact creature" | `{ "creature": { "types": ["artifact"] } }` |
| "with power 4 or greater", "with mana value 3 or less" | `{ "creature": { "power": { "at_least": 4 } } }`, `{ "permanent": { "mana_value": { "at_most": 3 } } }` (also `toughness`) |
| "with mana value equal to the number of charge counters on this" | `{ "permanent": { "mana_value": { "equal": { "counters": { "of": "self", "kind": "charge" } } } } }`: a bound is any amount; a sacrificed source counts as it last existed (CR 608.2h) |
| "Human", "non-Doctor" | `{ "creature": { "subtypes": ["human"] } }`, `{ "creature": { "not_subtypes": ["doctor"] } }` |
| "legendary", "nonlegendary" | `{ "creature": { "supertypes": ["legendary"] } }`, `{ "creature": { "not_supertypes": ["legendary"] } }` |
| "token", "nontoken" | `{ "creature": { "token": true } }`, `{ "creature": { "token": false } }` |
| "with a counter on it", "with a +1/+1 counter on it" | `{ "creature": { "counters": true } }`, `{ "creature": { "counters": "+1/+1" } }` |
| "modified" (CR 700.9) | `{ "creature": { "modified": true } }` |
| "attacking", "tapped" | `{ "creature": { "attacking": true } }`, `{ "creature": { "tapped": true } }` |
| "land, or creature with power 6 or greater" | `{ "one_of": [{ "permanent": { "any_of": ["land"] } }, { "creature": { "power": { "at_least": 6 } } }] }` |
| "noncreature spell" | `{ "spell": { "not": ["creature"] } }` |

| "with flying", "with flying or reach", "without flying" | `{ "creature": { "keywords": ["flying"] } }`, `{ "creature": { "keywords": ["flying", "reach"] } }`, `{ "creature": { "not_keywords": ["flying"] } }` (current keywords: granted ones count, CR 702.1) |
| "of the chosen color / creature type / card type", "not of the chosen type" | `{ "creature": { "subtypes": "chosen" } }`, `{ "spell": { "colors": "chosen" } }`, `{ "permanent": { "types": "chosen" } }`, `{ "creature": { "not_subtypes": "chosen" } }` (see 4.15) |

### 4.5 Who an effect applies to: the `to` selector

| Selector | Oracle words |
| --- | --- |
| `{ "target": 0 }` | "target …" (the 1st declared target; `1` is the 2nd, …) |
| `"you"` | "you" ("you gain 3 life", "draw a card") |
| `"each_opponent"` | "each opponent" |
| `"self"` | "this creature" / the card's own name, on a permanent |
| `"attached"` | "equipped creature" / "enchanted creature", on an Equipment or Aura |
| `{ "each": "creature", "controller": "you" }` | "creatures you control", "each creature you control" |
| `{ "each": "creature", "controller": "opponent" }` | "creatures your opponents control" |
| `{ "each": "creature" }` | "each creature", "all creatures" |
| `{ "result": 0 }` | "it" / "that card" / "the token": what effect 0 of the same list moved or created (CR 400.7j) |

### 4.5a Results, optional effects and delayed triggers

Every effect records the objects it moved or created (the new object ids, CR 400.7).
A later effect of the same effect list names them with `{ "result": n }`, where `n`
is the earlier effect's index (inside a mode: the index within that mode's list).
Lists nested in a `may` or a `delayed_trigger` see the results of their parent's
earlier effects.

```json
[{ "exile": { "to": { "target": 0 } } },
 { "return_to_battlefield": { "to": { "result": 0 } } }]
```
is a flicker ("exile …, then return it to the battlefield under its owner's control").

- `may` (CR 118.12): `{ "may": { "effects": [...], "then": [...], "otherwise": [...] } }`
  is "you may [effects]. If you do, [then]. If you don't, [otherwise]." The controller
  answers yes/no as it resolves (an `effect_choice`); yes is offered only when the
  optional part can be done fully (CR 118.3).
- `delayed_trigger` (CR 603.7): `{ "delayed_trigger": { "when": { "step_begins":
  { "step": "end", "whose": "each" } }, "effects": [{ "sacrifice": { "to": { "result": 0 } } }] } }`
  is "… at the beginning of the next end step". It triggers once, with the controller
  and source of what created it; a remembered object that has changed zones is not
  affected (CR 603.7c).
- `{ "was_cast": true }` as a triggered ability's `if` is "if you cast it" (CR 603.4).

### 4.5b More trigger shapes

| Shape | Data |
| --- | --- |
| "Whenever ~ becomes tapped" | `{ "becomes_tapped": {} }` |
| "Whenever one or more +1/+1 counters are put on ~" | `{ "counters_placed": { "counter": "+1/+1" } }` |
| one of your creatures is targeted by an opponent's spell or ability | `{ "becomes_target": { "subject": { "each": "creature", "controller": "you" }, "by": "opponent" } }` |
| "Whenever a card leaves your graveyard" / "one or more cards leave" | `{ "leaves_graveyard": {} }` / `{ "leaves_graveyard": { "batched": true } }` |
| "Whenever an opponent activates an ability" (not mana abilities) | `{ "activates_ability": { "controller": "opponent" } }` |
| "When you cast this spell" | `{ "cast": { "self": true } }` |
| you cast a spell that is a creature or a Spacecraft | `{ "cast": { "spell": { "one_of": [{ "spell": { "any_of": ["creature"] } }, { "spell": { "subtypes": ["spacecraft"] } }] } } }` |
| a number chosen as it enters (0 to 10) / spells whose mana value is that number | ability `{ "choose_number": { "min": 0, "max": 10 } }` / `"cast": { "mana_value": "chosen" }` |
| a nonland card name chosen as it enters / spells or sources with that name | ability `{ "choose_card_name": { "not": ["land"] } }` / `"name": "chosen"` on `cast` or `activates_ability` |
| triggers at most once per turn | `"limit": "once_each_turn"` on the `triggered` ability |
| a triggered ability that works from the graveyard ("return this card from your graveyard") | `"zone": "graveyard"` on the `triggered` ability (CR 113.6k) |
| "that creature", "that player", "that many" | selectors `{ "triggering": "object" }`, `{ "triggering": "player" }`, amount `{ "triggering": "amount" }` |
| the triggering spell is a Saga | condition `{ "triggering": { "spell": { "subtypes": ["saga"] } } }` |
| the targeted creature dying later this turn | `{ "delayed_trigger": { "when": { "dies": { "subject": "watched" } }, "watch": { "target": 0 }, "this_turn": true, "effects": [...] } }`; effects name the watched objects with the selector `"watched"` |
| each of your creatures entering for the rest of the turn | `delayed_trigger` with `"this_turn": true` (it triggers each time until the turn ends) |
| "at the beginning of the next combat this turn, gain control of that creature" | `{ "delayed_trigger": { "when": { "step_begins": { "step": "beginning_of_combat" } }, "this_turn": "once", "watch": { "target": 0 }, "effects": [{ "gain_control": { "to": "watched", "duration": "end_of_turn" } }] } }` (`"once"`: only the next time, and only this turn) |
| optional A; if it was done, a reflexive trigger B with its own target | `{ "may": { "effects": [A], "then": [{ "reflexive_trigger": { "targets": [...], "effects": [B] } }] } }` |
| a targeted opponent decides whether A happens; B if not | `{ "may": { "chooser": { "target": 0 }, "effects": [A], "otherwise": [B] } }` |
| your life gain makes your permanents' triggered abilities trigger one extra time | `{ "additional_triggers": { "cause": "you_gain_life" } }` |
| tapped unless its controller has two other lands / a trigger only if it came in untapped | `{ "enters_tapped_unless": { "condition": { "controls": { "each": "land", "controller": "you" }, "at_least": 2 } } }` / `{ "enters": { "untapped": true } }` |
| returned to the battlefield carrying a +1/+1 counter | `"counters": { "+1/+1": 1 }` on `return_to_battlefield` |

Zone-change and keyword-action triggers. Leaving the battlefield and sacrificing look back in time
(CR 603.10a): the permanent is matched as it last existed, its own ability triggers although it has
left, its effects read its last known counters and power (`{ "counters": { "of": "self" } }`), and
permanents that leave at the same time (one effect, or state-based actions) see each other leave.
`"batched": true` is "one or more": one trigger per event batch, and `{ "triggering": "amount" }` is
how many occurrences the batch had.

| Shape | Data |
| --- | --- |
| "When this leaves the battlefield" / "is put into exile from the battlefield" | `{ "leaves_battlefield": {} }` / `{ "leaves_battlefield": { "to": "exile" } }` |
| "Whenever another creature you control leaves the battlefield" | `{ "leaves_battlefield": { "subject": { "each": "creature", "controller": "you", "other": true } } }` |
| "When this enters or leaves the battlefield" | `{ "any_of": [{ "enters": {} }, { "leaves_battlefield": {} }] }` |
| "Whenever you sacrifice another permanent" / "a Food" | `{ "sacrifices": { "subject": { "each": "permanent", "controller": "you", "other": true } } }` / `"each": { "artifact": { "subtypes": ["food"] } }` |
| "Whenever you discard one or more cards, create that many …" | `{ "discards": { "batched": true } }`, amount `{ "triggering": "amount" }` |
| "Whenever you cycle a card" | `{ "cycles": {} }` (a cycled card is also discarded: `discards` triggers too) |
| "Whenever you scry or surveil" | `{ "any_of": [{ "scries": {} }, { "surveils": {} }] }` (scry 0 isn't a scry) |
| "Whenever equipped creature becomes untapped" | `{ "becomes_untapped": { "subject": "attached" } }` |
| "Whenever one or more creature cards are put into your graveyard from anywhere" | `{ "put_into": { "zone": "graveyard", "card": "creature", "batched": true } }` |
| "Whenever one or more cards are put into exile from graveyards and/or the battlefield" | `{ "put_into": { "zone": "exile", "from": ["graveyard", "battlefield"], "controller": "any", "batched": true } }` |
| "during your turn" | `"if": { "your_turn": true }` on the `triggered` ability |

```json
{ "triggered": { "when": { "leaves_battlefield": {} }, "targets": [{ "creature": { "controller": "you" } }],
                 "effects": [{ "add_counters": { "counter": "+1/+1", "amount": { "counters": { "of": "self", "kind": "+1/+1" } },
                                                 "to": { "target": 0 } } }] } }
```

### 4.6 Effects

See `docs/reference/effects.md` for the generated list. Currently:

| Effect | Oracle text | Data |
| --- | --- | --- |
| `deal_damage` | "deals N damage to …" | `{ "deal_damage": { "amount": N, "to": … } }` |
| `pump` | "gets +X/+Y until end of turn" | `{ "pump": { "power": X, "toughness": Y, "to": … } }` |
| `pump` | "get -1/-0 until your next turn" | `{ "pump": { "power": -1, "toughness": 0, "duration": "until_your_next_turn", "to": … } }` (ends as your next turn begins, CR 611.2a) |
| `add_counters` | "put N +1/+1 counters on …" | `{ "add_counters": { "counter": "+1/+1", "amount": N, "to": … } }` (any counter name: `+1/+1`, `stun`, `shield`, `oil`, a keyword; see `docs/reference/counters.md`) |
| `gain_life` | "you gain N life" | `{ "gain_life": { "amount": N } }` (`to` defaults to `"you"`) |
| `lose_life` | "each opponent loses N life" | `{ "lose_life": { "amount": N, "to": "each_opponent" } }` |
| `draw` | "draw N cards" | `{ "draw": { "amount": N } }` (`to` defaults to `"you"`) |
| `destroy` | "destroy target …" | `{ "destroy": { "to": … } }` |
| `counter` | "counter target spell" | `{ "counter": { "to": { "target": 0 } } }` |

### 4.7 Mana effects, X and cost changes

| Oracle text | Data |
| --- | --- |
| "Add {R}{R}{R}." (a spell or trigger, not a mana ability) | `{ "add_mana": { "produce": "{R}{R}{R}" } }` |
| "Add two mana of any one color." | `{ "add_mana": { "amount": 2, "color": "any_one" } }` |
| "Add two mana in any combination of colors." | `{ "add_mana": { "amount": 2, "color": "any" } }` |
| "Add {C}{C}. Spend this mana only to cast spells." | `{ "add_mana": { "produce": "{C}{C}", "spend_only": { "spells": "card" } } }` |
| `{X}` in the cost, "deals X damage" | `"mana_cost": "{X}{R}"`, `{ "deal_damage": { "amount": "x", ... } }` |
| "... costs {2} less to cast if it targets a tapped creature." | `{ "cost_reduction": { "amount": 2, "if": { "targets": { "creature": { "tapped": true } } } } }` |
| "... costs {1} less to cast if a creature is attacking you." | `{ "cost_reduction": { "amount": 1, "if": { "attacked": true } } }` |
| "Affinity for artifacts" | `{ "cost_reduction": { "amount": { "count": { "each": "artifact", "controller": "you" } } } }` |
| "Noncreature spells you cast cost {1} less to cast." | `{ "cost_modifier": { "spells": { "not": ["creature"] }, "reduce": 1 } }` |
| "Spells your opponents cast cost {1} more to cast." | `{ "cost_modifier": { "caster": "opponent", "increase": 1 } }` |
| "This ability costs {1} less to activate for each land you control." | `"cost_reduction": { "amount": {...} }` inside the `activated` ability |

An activated ability without targets that adds mana is a *mana ability* (CR 605.1a):
use `mana`, not `activated` with `add_mana` (validation rejects it). In an
enters-the-battlefield trigger, `"x"` is the X the permanent was cast with (CR 107.3m).

### 4.8 Auras and Equipment

Give the card the subtype `aura` (enchantments only) or `equipment` (artifacts only).

| Oracle text | Data |
| --- | --- |
| "Enchant creature" | `{ "enchant": "creature" }`. Any permanent filter works, e.g. `{ "enchant": { "permanent": { "any_of": ["artifact", "creature"] } } }`. Every Aura needs exactly one. The Aura spell targets with it (CR 303.4a), so don't add a `spell` ability. |
| "Equip {2}" | `{ "equip": { "cost": [{ "mana": "{2}" }] } }`. Only Equipment have it. |
| "Equipped creature gets +2/+0 and has trample." | `{ "static": { "affects": "attached", "pump": { "power": 2, "toughness": 0 }, "keywords": ["trample"] } }` |
| "Whenever equipped creature attacks, …" | `{ "triggered": { "when": { "attacks": { "subject": "attached" } }, … } }` |
| "When this Aura enters, enchanted creature gains … until end of turn." | an `enters` trigger with `{ "grant": { …, "to": "attached" } }` |
| "attach it to target creature you control" | `{ "attach": { "to": { "target": 0 } } }` |
| "create an Equipment token …, then attach it to this creature" | `create_token`, then `{ "attach": { "to": "self", "attachment": { "result": 0 } } }` |
| "… with a Communicator attached to it" | the filter restriction `{ "creature": { "attached_subtypes": ["communicator"] } }` |

Not supported yet: Auras that enchant players, Equipment that enters attached or
equips for a non-mana cost, and granted activated abilities ("equipped creature has
'{T}: …'"). Granted triggered abilities are the static `abilities` list (4.11).

### 4.9 Station cards, Sagas and other set mechanics

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
  "Assimilate a creature card exiled with this. If you can't, exile up to one target creature an
  opponent controls" chooses among the linked cards as it resolves (`choose: true`, `for` a card spec),
  and the exile only happens when the assimilate put nothing onto the battlefield (CR 701.72c, 607.2a;
  the target is still chosen when the trigger is put on the stack, CR 603.3d):

  ```json
  { "triggered": { "when": { "any_of": [{ "enters": {} }, { "attacks": {} }] },
                   "targets": [{ "filter": { "creature": { "controller": "opponent" } }, "optional": true }],
                   "effects": [
                     { "assimilate": { "to": "exiled_with", "for": { "types": ["creature"] }, "choose": true } },
                     { "exile": { "to": { "target": 0 }, "link": true,
                                  "if": { "amount": { "count": { "result": 0 } }, "at_most": 0 } } }] } }
  ```
- **"As this enters" choices on permanents put onto the battlefield by effects** (CR 614.12a).
  Nothing to write: when `return_to_battlefield`, `search_library`, `dig`, `reveal_until`,
  `choose_cards` (`put: "battlefield"`), `assimilate` or `create_token` puts a permanent with
  `choose_number`, `choose_card_name` or `enters_tapped_unless_pay_life` onto the battlefield,
  its controller-to-be answers an `enter_choice` (with `effect: true`) for each one in turn, then
  they all enter at once. "Exile the top four cards of your library; put all permanent cards
  exiled this way onto the battlefield under your control":

  ```json
  [{ "exile_top": { "amount": 4 } },
   { "return_to_battlefield": { "to": { "result": 0 }, "under": "you" } }]
  ```
- **Strange new worlds** is an ability word: drop it. "The number of differently
  named lands you control" is the amount
  `{ "distinct_names": { "each": "land", "controller": "you" } }`.

### 4.10 Casting and playing from other zones

- **Beam me up** (CR 702.196): `{ "beam_me_up": { "cost": "{3}{W}" } }` on an instant
  or sorcery. A permanent that gives the cards in its controller's graveyard beam me up
  during their main phase, for each card's own mana cost, has the ability
  `"grants_beam_me_up"`; that permanent can't be the creature returned for spells cast
  its way. A creature that can never be returned for a beam me up cost has the keyword
  `"cant_be_beamed_up"`.
- **Keyword alternative costs** (CR 118.9): each is an ability with a `cost`, either a
  mana string or a list of costs like kicker's (mana plus chosen costs such as
  `tap_permanents`). A card with one gets an extra cast option
  `{type: "cast", object: id, via: "alt:<ability ref>"}` while the keyword works:
  - `{ "flashback": { "cost": "{2}{R}" } }` (CR 702.34): instant or sorcery, from your
    graveyard; it's exiled whenever it would leave the stack. "Flashback—{1}{U}, tap two
    untapped creatures you control" is
    `{ "flashback": { "cost": [{ "mana": "{1}{U}" }, { "tap_permanents": { "count": 2 } }] } }`.
  - `{ "harmonize": { "cost": "{4}{G}" } }` (CR 702.180): from your graveyard; while
    casting you may tap one untapped creature you control (a `choose_cost` decision,
    `{type: "cost"}` taps none) to reduce the total cost by its power. Exiled like flashback.
  - `{ "mayhem": { "cost": "{1}{R}" } }` (CR 702.187): from your graveyard if you
    discarded the card this turn. `"mayhem"` without a cost lets you play it (a land too)
    from your graveyard for its normal costs.
  - `{ "warp": { "cost": "{1}{R}" } }` (CR 702.185): from your hand; the permanent is
    exiled at the beginning of the next end step, and its owner may cast it from exile
    after that turn (`via: "warped"`) for as long as it stays there.
  - `{ "evoke": { "cost": "{R/W}{R/W}" } }` (CR 702.74): on a permanent card; it comes
    with "When this enters, if its evoke cost was paid, sacrifice it".
  - `{ "web_slinging": { "cost": "{2}{G}" } }` (CR 702.188): also return a tapped
    creature you control to its owner's hand (a `choose_cost` decision).
  - `{ "sneak": { "cost": "{1}{B}" } }` (CR 702.190): during your declare blockers step,
    at instant speed, also return an unblocked attacking creature you control; a
    permanent spell enters tapped and attacking what that creature attacked.

  **Convoke** (CR 702.51) is the keyword `"convoke"`: while paying, the `pay_cost`
  option `{type: "convoke", object: id}` taps an untapped creature you control to pay
  {1} or one mana of its color.

  How a spell was cast is a condition (CR 400.7d): `{ "cast_with": "evoke" }` (its
  keyword cost was paid), `{ "cast_from": "graveyard" }` (also `hand`, `exile`,
  `library`, `outside`; "from anywhere other than your hand" is
  `{ "not": { "cast_from": "hand" } }`), and `{ "cast_with_this_turn": "warp" }` ("if a
  spell was warped this turn"). The permanent a spell becomes, and its triggered
  abilities, remember it. "Draw a card. If this spell was cast from a graveyard, draw
  two cards instead. Flashback {3}{U}":
  ```json
  { "name": "Second Glance", "mana_cost": "{1}{U}", "types": ["sorcery"],
    "abilities": [
      { "spell": { "effects": [
        { "draw": { "amount": 1, "if": { "not": { "cast_from": "graveyard" } } } },
        { "draw": { "amount": 2, "if": { "cast_from": "graveyard" } } } ] } },
      { "flashback": { "cost": "{3}{U}" } } ] }
  ```
- **A card castable from its owner's graveyard or exile**:
  `{ "play_from": { "zone": "graveyard" } }`; add `"enters_with": { "finality": 1 }`
  when a permanent spell cast that way gets a finality counter.
- **A permanent's permission** for its controller's own cards: give `cards` a card
  spec. Casting an artifact spell from the top of the library once per turn (on your
  own turns) is `{ "play_from": { "zone": "library_top", "cards": { "types":
  ["artifact"] }, "once_each_turn": true } }`; playing lands from the top uses
  `"cards": { "types": ["land"] }, "play": "play"`. Seeing the top card of your library
  at all times (CR 401.5) is the ability `"look_at_top"`.
- **Several zones, and outside the game** (CR 400.11a): `zones` lists the zones
  instead of `zone`, and `"outside"` means the cards the player owns outside the game
  (the deck's `outside` list, see [Decks](#6-decks)). With `once_each_turn`, all the
  zones share one use per turn. "Once during each of your turns, you may play a
  permanent card you own from outside the game or from your graveyard":
  ```json
  { "play_from": { "zones": ["outside", "graveyard"], "cards": { "permanent": true },
                   "play": "play", "once_each_turn": true } }
  ```
  A land played this way uses the turn's land play (CR 305.2).
- **Impulse draw**: `exile_top` (or `exile_until` with `"until": "nonland"`) followed by
  `{ "play_permission": { "to": { "result": 0 }, "duration": "end_of_your_next_turn" } }`
  (`end_of_turn` for the current turn only, `while_exiled` for as long as the cards stay
  in exile). `not_types: ["land"]` keeps only the nonland card an exile-until found;
  `"choose": "one_per_owner"` with `"for": { "types": ["land"] }` makes the controller
  pick one matching card per owner among the exiled ones.
- **Exiled face down** (CR 406.3): `"face_down": true` on `exile_top`; `looker` names the
  players who may look at the cards (default: you). A face-down card has no
  characteristics, its id doesn't name it (`face_down#12`), and views and events show
  it only to the lookers. `play_permission` takes `to_player` (see below; a face-down
  card needs a player who may look at it, CR 406.3b) and `any_mana_type: true` ("mana of any type can be spent to cast those spells", CR 609.4b).
  The card is turned face up as it's played. "Target opponent exiles the top card of your
  library face down; you exile the top two cards of theirs face down; each card's exiler
  may play it while it stays exiled, spending mana as though it were mana of any type":

  ```json
  { "spell": { "targets": ["opponent"], "effects": [
    { "exile_top": { "amount": 1, "face_down": true, "looker": { "target": 0 } } },
    { "exile_top": { "amount": 2, "to": { "target": 0 }, "face_down": true } },
    { "play_permission": { "to": { "result": 0 }, "to_player": { "target": 0 }, "duration": "while_exiled", "any_mana_type": true } },
    { "play_permission": { "to": { "result": 1 }, "duration": "while_exiled", "any_mana_type": true } } ] } }
  ```
- **Who may play it, and for how much** (CR 108.3, 601.2f): `play_permission` takes
  `to_player`, which is `"controller"` (the default), `"owner"` (each card's owner) or a
  player selector such as `{ "target": 0 }`. It also takes `cost_increase`: a spell
  cast with this permission costs that much more generic mana. This applies only when
  the permission is the one used to cast it. "Look at target opponent's hand and exile
  a nonland card from it. For as long as that card remains exiled, its owner may play
  it. A spell cast this way costs {2} more":
  ```json
  [{ "look_at_hand": { "to": { "target": 0 } } },
   { "choose_cards": { "from": { "hand": { "target": 0 } }, "for": { "not_types": ["land"] }, "put": "exile" } },
   { "play_permission": { "to": { "result": 1 }, "to_player": "owner", "duration": "while_exiled",
                          "cost_increase": 2 } }]
  ```
- **Casting while resolving without paying mana costs** (CR 608.2g):
  `{ "cast_free": { "to": { "result": 0 }, "max_mana_value": 3, "count": "any" } }`;
  with no `to` it offers matching cards from your hand. **Discover N** (CR 701.57) is
  `{ "discover": { "amount": 5 } }`.

### 4.11 Amounts, conditions, "this turn" and static abilities

The full lists are in `lib/enjine/mechanics/values.rb` (`Amount`, `Condition`).

| Oracle words | Data |
| --- | --- |
| "+X/+X, where X is its power" | `{ "pump": { "power": { "power": "self" }, "toughness": { "power": "self" }, "to": … } }` |
| "-X/-X" | `{ "times": [<amount>, -1] }`; also `plus`, `divide` (rounds down, CR 107.1a) |
| "the number of creature types among …" | `{ "distinct_types": <selector> }` |
| "the number of counters on it" | `{ "counters": { "of": "self", "kind": "quest" } }` (no `kind`: every counter) |
| "cards in your graveyard", "greatest power among …" | `{ "graveyard_size": "you" }`, `{ "greatest_power": <selector> }` |
| "life you gained / that player lost this turn" | `{ "life_gained_this_turn": "you" }`, `{ "life_lost_this_turn": "each_opponent" }` |
| an amount an earlier effect changed (life it made a player lose) | `{ "this_way": n }` (effect n of the same list) |
| N or more cards drawn by an earlier effect; "if you do" after a mandatory effect | `{ "amount": { "count": { "result": n } }, "at_least": 3 }` |
| a trigger that also needs total power N or more of your creatures | `"while": { "amount": { "power": { "each": "creature", "controller": "you" } }, "at_least": 8 }` on a trigger (checked only as it triggers) |
| "if a creature died this turn", "if you've cast a noncreature spell this turn" | `{ "amount": { "died_this_turn": { "each": "creature" } }, "at_least": 1 }`, `{ "spells_cast_this_turn": { "by": "you", "matching": { "spell": { "not": ["creature"] } } } }` |
| raid: "if you attacked this turn" | `{ "you_attacked_this_turn": true }` |
| "if you attacked with three or more Merfolk this turn" | `{ "amount": { "attackers_this_turn": { "each": { "creature": { "subtypes": ["merfolk"] } }, "controller": "you" } }, "at_least": 3 }` |
| "if a permanent left the battlefield under your control this turn" / "a nonland permanent left the battlefield this turn" | `{ "amount": { "left_this_turn": { "controller": "you" } }, "at_least": 1 }` / `{ "left_this_turn": { "each": { "permanent": { "not": ["land"] } } } }` |
| "the number of permanents you've sacrificed this turn" | `{ "sacrificed_this_turn": { "controller": "you" } }` |
| "if one or more cards were put into exile this turn" | `{ "amount": { "exiled_this_turn": {} }, "at_least": 1 }` |
| "if you've drawn two or more cards this turn", "each card you've discarded this turn" | `{ "amount": { "cards_drawn_this_turn": "you" }, "at_least": 2 }`, `{ "cards_discarded_this_turn": "you" }` |
| "if you gained life this turn" | `{ "amount": { "life_gained_this_turn": "you" }, "at_least": 1 }` |
| "if a creature died under your control this turn" | `{ "amount": { "died_this_turn": { "each": "creature", "controller": "you" } }, "at_least": 1 }` |
| the Nth resolution of this ability this turn | `{ "nth_resolution": 2 }` |
| "if it isn't a creature", "if it attacked this turn" | `{ "not": { "source": "creature" } }`, `{ "attacked_this_turn": true }` |
| "its controller creates …" | `"to": { "controller_of": { "target": 0 } }` |
| a fixed mana symbol added a computed number of times | `{ "add_mana": { "produce": "{G}", "amount": <amount> } }` |

Static abilities (`static`) take `"affects": "self"` and an `if` ("as long as …",
"during your turn": `{ "your_turn": true }`); `pump` amounts may be computed ("gets
+1/+0 for each …"); `creature_types` sets the creature types;
`abilities` grants triggered or mana abilities (each matching permanent has them). A `*` power or toughness is an amount in the card data (`"power": { "count":
… }`, CR 604.3). Setting creature types until end of turn is `set_creature_types`; setting
base power and toughness is `set_base_power_toughness` (`duration: "indefinite"` lasts while it stays).
A token's or color-indicator card's colors are `"colors": ["R"]`; filters take `"colors"`.

### 4.12 Libraries, hands, graveyards and edicts

Generic shapes (N, [quality] and [zone] stand for whatever the card says):

| Shape | Data |
| --- | --- |
| look at the top N; you may reveal a [quality] card among them and put it into your hand; the rest go to the bottom in a random order | `{ "dig": { "amount": N, "for": spec, "optional": true, "reveal": "chosen", "put": "hand" } }` |
| look at the top N; one goes to your hand, the rest to your graveyard | `{ "dig": { "amount": N, "rest": "graveyard" } }` |
| reveal the top N; every [quality] card goes onto the battlefield tapped | `{ "dig": { "amount": N, "reveal": "all", "for": spec, "count": "all", "put": "battlefield", "tapped": true } }` |
| the rest go to the bottom in any order | `"rest": "bottom_any"` |
| reveal from the top until N [quality] cards are revealed; put them into [zone] | `{ "reveal_until": { "for": spec, "count": N, "put": "battlefield" } }` |
| exile the top N; the permanent cards exiled this way enter the battlefield | `exile_top`, then `{ "return_to_battlefield": { "to": { "result": 0 }, "under": "you" } }` |
| mill N; you may put a [quality] card from among them into your hand | `mill`, then `{ "choose_cards": { "from": { "result": 0 }, "for": spec, "optional": true, "put": "hand" } }` |
| return a [quality] card from your graveyard to your hand; if you can't, [effect] | `{ "choose_cards": { "from": { "graveyard": "you" }, "for": spec, "put": "hand", "otherwise": [ … ] } }` |
| look at a player's hand; you may choose a [quality] card; if you do, [effect] | `{ "choose_cards": { "from": { "hand": { "target": 0 } }, "look": true, "for": spec, "optional": true, "put": "exile", "then": [ … ] } }` |
| each player sacrifices a [quality] permanent of their choice | `{ "sacrifice_choice": { "filter": filter, "to": { "each": "player" } } }` (`"count": "any"`: any number) |
| exile a target card in a graveyard; return a target card from your graveyard to your hand | `exile` / `return_to_hand` with a `graveyard_card` target |
| its owner puts it on the top or bottom of their library, as they choose | `{ "put_in_library": { "to": { "target": 0 }, "position": "owner_choice" } }` |
| cards exiled with this; exile until this leaves the battlefield | `exile` with `"link": true` / `"until_source_leaves": true`; the selector `"exiled_with"` |
| that permanent's controller may search their library | `search_library` with `"searcher": { "controller_of": { "target": 0 } }, "may": true` |
| a permanent explores | `{ "explore": { "to": … } }` |
| you return a [quality] permanent you control to its owner's hand (chosen, not targeted) | `{ "return_choice": { "filter": { "permanent": { "any_of": ["land"], "controller": "you" } } } }` (same `count` and `to` as `sacrifice_choice`) |

### 4.13 Turn structure: untap step, land plays and phasing

| Shape | Data |
| --- | --- |
| "You may play an additional land on each of your turns" (CR 305.2) | ability `"additional_land_plays"` (each instance is one more land play; lands put onto the battlefield by effects don't count) |
| "You may choose not to untap this during your untap step" (CR 502.3) | ability `"may_not_untap"` (its controller answers an `untap_choice` decision in their untap step while it's tapped) |
| phasing (CR 702.26a) | keyword `"phasing"` |
| "[permanents] phase out" (CR 702.26) | `{ "phase_out": { "to": { "each": { "permanent": { "any_of": ["artifact", "creature"] } } } } }` |
| "Permanents can't phase in" | ability `"cant_phase_in"` |
| "for as long as this remains tapped, … triggered abilities trigger an additional time" (CR 603.2d, 611.2b) | `{ "additional_triggers": { "to": { "target": 0 }, "duration": "while_source_tapped" } }` |
| "when one or more [kind] counters are put on this for the first time each turn" | `{ "counters_placed": { "counter": "charge", "first_time_this_turn": true } }` |
| "it becomes a [type] with base power and toughness N/M and gains '…'" (layers 4, 6, 7b) | `become`, below |

A phased-out permanent keeps its id, counters and attachments but is treated as though it
doesn't exist (the view lists it under `phased_out`). It phases in during the untap step of
the player who controlled it as it phased out; Auras and Equipment attached to it phase out and
back in with it.

```json
{ "become": { "creature_types": ["goblin", "scout"],
              "base_power_toughness": { "power": 3, "toughness": 4 },
              "abilities": ["additional_land_plays",
                            { "triggered": { "when": { "becomes_tapped": {} },
                                             "effects": [{ "surveil": { "amount": 1 } }] } }],
              "duration": "indefinite", "to": "self" } }
```

`creature_types` replaces the creature types, `abilities` may hold triggered, mana,
`play_from` (for other cards) and `additional_land_plays` abilities, and `duration` is
`end_of_turn` (default) or `indefinite` (for as long as it stays on the battlefield). An
activated ability that only works while it has a subtype uses
`"only_if": { "source": { "creature": { "subtypes": ["rogue"] } } }`.

### 4.14 Copies (CR 707)

A copy has the **copiable values** of what it copies: the values printed on its card,
as changed by other copy effects and their exceptions, and nothing else: no counters,
tapped status, damage or other effects (CR 707.2). Every copy primitive names what it
copies with `of` (a selector; `"self"` is the source in any zone, even a card that
exiled itself from a graveyard to pay the cost) and takes the same `except` object for
"except …" (CR 707.9a-b), which a copy of the copy keeps:
`{ "legendary": false, "keywords": ["menace"], "types": [...], "subtypes": [...],
"supertypes": [...], "name": "…", "power": 1, "toughness": 1, "colors": [] }`.

| Oracle words | Data |
| --- | --- |
| "create a token that's a copy of target creature, except it isn't legendary" | `{ "create_token_copy": { "of": { "target": 0 }, "except": { "legendary": false } } }` (`amount`, `tapped`, `to`: the players who create them) |
| "That token gains haste. Sacrifice it at the beginning of the next end step." | `grant` and `delayed_trigger` with `{ "result": n }` (the tokens are the effect's result) |
| "exile target creature card from your graveyard, create a token that's a copy of it" | `exile`, then `{ "create_token_copy": { "of": { "result": 0 } } }` |
| "you may have this creature enter as a copy of any artifact or creature on the battlefield …, with the same counters" | `{ "enter_as_copy": { "of": { "permanent": { "any_of": ["artifact", "creature"] } }, "except": { "legendary": false }, "with_counters": true } }` |
| "… becomes a copy of target Equipment until end of turn" | `{ "become_copy": { "to": …, "of": { "target": 0 } } }` (`"duration": "permanent"` while it stays) |
| "When you cast this spell, copy it." | a `{ "cast": { "self": true } }` trigger with `{ "copy_spell": { "of": "self" } }` |
| "copy target instant or sorcery spell; you may choose new targets for the copy" | `{ "copy_spell": { "of": { "target": 0 }, "new_targets": true } }` |
| "copy that card X times; you may cast the copies without paying their mana costs" | `{ "copy_card": { "of": { "result": 0 }, "amount": "x" } }`, then `cast_free` with `"to": { "result": 1 }, "count": "any"` |
| "create a copy of this card; you may cast the copy" (paying its costs) | `{ "copy_card": { "of": "self" } }`, then `{ "cast": { "to": { "result": 0 } } }` |
| "that card gains '…'" (also an exiled card) | `{ "grant_ability": { "to": { "result": 0 }, "ability": { … } } }` |
| "Exile a card from your hand: …" (a cost) | `{ "exile_from_hand": {} }` (`count`, `card`: a card spec) |
| "activate only if this card is exiled" | `"zone": "exile"` on the activated ability |
| "Changeling (This object is every creature type.)" | `"keywords": ["changeling"]` |

A token copy is a token (the filter `"token": true` matches it). A copy of a permanent
spell becomes a token as it resolves (CR 608.3f). A spell copy that leaves the stack, or
a card copy outside the stack and battlefield, ceases to exist (CR 707.10a).

```json
{ "name": "Example Duplicant", "mana_cost": "{3}{U}", "types": ["creature"], "subtypes": ["shapeshifter"],
  "power": 0, "toughness": 0,
  "abilities": [{ "enter_as_copy": { "of": "creature", "except": { "legendary": false } } },
                { "activated": { "cost": [{ "mana": "{2}" }], "targets": [{ "creature": { "controller": "you" } }],
                                 "effects": [{ "create_token_copy": { "of": { "target": 0 } } },
                                             { "grant": { "keywords": ["haste"], "to": { "result": 0 } } }] } }] }
```

### 4.15 Chosen colors, creature types, card types and words (CR 607.2d)

A choice is remembered on an object; "the chosen …" reads it. Made **as a permanent enters**
(an ability, CR 614.12; the enter_choice decision) it is remembered on the permanent, and the
permanent's other abilities read it. Made **while a spell or ability resolves** (an effect, an
effect_choice decision) it is remembered on that spell or ability, and its later effects read
it (and, failing that, its source's choice).

| Oracle words | Data |
| --- | --- |
| "As this enters, choose a color / creature type / card type" | ability `{ "choose_color": {} }`, `{ "choose_creature_type": {} }`, `{ "choose_card_type": {} }` |
| "As this enters, choose Khans or Dragons" (CR 607.2f) | ability `{ "choose_option": { "options": ["khans", "dragons"] } }` |
| "Choose a color / creature type / card type." / "Choose odd or even." (on resolution) | effect `{ "choose_color": {} }` (same names; `to`: who chooses, default you), `{ "choose_option": { "options": ["odd", "even"] } }` |
| "… of the chosen color / type / card type", "not of the chosen type" | filter `"colors": "chosen"`, `"subtypes": "chosen"`, `"types": "chosen"`, `"not": "chosen"`, `"not_subtypes": "chosen"` |
| "If odd was chosen …", "• Khans — …" | condition `{ "chosen": "odd" }` (in an effect's `if`, a static's `if`, a trigger's `if`) |

Nothing matches "the chosen type" while nothing was chosen. The options offered are the five
colors (CR 105.4), every creature type (CR 205.3m) and the card types (CR 205.2a).

```json
{ "name": "Example Kin Banner", "mana_cost": "{3}", "types": ["artifact"],
  "abilities": [{ "choose_creature_type": {} },
                { "static": { "affects": { "each": { "creature": { "subtypes": "chosen" } }, "controller": "you" },
                              "pump": { "power": 1, "toughness": 1 } } },
                { "triggered": { "when": { "cast": { "spell": { "spell": { "subtypes": "chosen" } } } },
                                 "effects": [{ "draw": { "amount": 1 } }] } }] }
```

```json
{ "name": "Example Kin Recall", "mana_cost": "{3}{B}", "types": ["sorcery"],
  "abilities": [{ "spell": { "effects": [
    { "choose_creature_type": {} },
    { "return_to_battlefield": { "to": { "each": { "graveyard_card": { "controller": "you", "any_of": ["creature"],
                                                                       "subtypes": "chosen" } } } } }] } }] }
```

### 4.16 Vehicles, type changes, exhaust and speed

**Vehicles and crew** (CR 301.7, 702.122). A Vehicle is an artifact with `"subtypes": ["vehicle"]`
and its printed `power`/`toughness` on the card: it has them only while it's a creature (CR 208.3).
"Crew N" is the ability `{ "crew": { "power": N } }`. Activating it asks a `choose_cost` decision per
creature to tap (other untapped creatures you control, summoning-sick ones too); once their total
power is N or more the player answers `done` (or taps more). It becomes an artifact creature until
end of turn.

```json
{ "name": "Example Hauler", "mana_cost": "{2}", "types": ["artifact"], "subtypes": ["vehicle"],
  "power": 4, "toughness": 3, "keywords": ["trample"],
  "abilities": [{ "crew": { "power": 2 } },
                { "triggered": { "when": { "becomes_crewed": {} },
                                 "effects": [{ "gain_life": { "amount": 1 } }] } }] }
```

| Oracle words | Data |
| --- | --- |
| "Whenever this Vehicle becomes crewed" | `{ "becomes_crewed": {} }` (its crew ability resolved, CR 702.122e) |
| "Whenever this creature crews a Vehicle, that Vehicle gets +2/+0" | `{ "crews_vehicle": {} }` (`subject` like other triggers) with `"to": { "triggering": "object" }` |
| "During turns other than yours, this Vehicle is an artifact creature" | `{ "static": { "affects": "self", "if": { "not": { "your_turn": true } }, "types": ["artifact", "creature"] } }` |
| "Target Vehicle becomes an artifact creature until end of turn" | `{ "become": { "types": ["artifact", "creature"], "to": { "target": 0 } } }` |

**Type-changing effects** (CR 205.1b, 613.1d-e). `become` adds card `types`, `supertypes` and
`subtypes` "in addition to its other types", sets `creature_types` (replacing the others), `colors`
(layer 5), grants `keywords` and `abilities` and sets `base_power_toughness`, for `duration`
`end_of_turn` (default) or `indefinite`. A permanent that becomes a creature without a P/T setting
has its printed power and toughness, or 0/0. A manland, "{1}{R}: This land becomes a 3/1 red
Elemental creature with haste until end of turn. It's still a land.":

```json
{ "activated": { "cost": [{ "mana": "{1}{R}" }],
                 "effects": [{ "become": { "types": ["creature"], "creature_types": ["elemental"], "colors": ["R"],
                                           "keywords": ["haste"],
                                           "base_power_toughness": { "power": 3, "toughness": 1 }, "to": "self" } }] } }
```

"Target creature becomes an artifact in addition to its other types" is `"types": ["artifact"]`;
"becomes a legendary Spider Hero in addition to its other types" is `"supertypes": ["legendary"],
"subtypes": ["spider", "hero"]`. Static abilities take `types` the same way.

**Exhaust** (CR 702.177). "Exhaust — {2}{G}: …" is an activated ability with `"exhaust": true`: it
can be activated only once for as long as the permanent stays. "Whenever you activate an exhaust
ability" is `{ "activates_ability": { "exhaust": true } }`.

```json
{ "activated": { "exhaust": true, "cost": [{ "mana": "{2}{G}" }],
                 "effects": [{ "add_counters": { "counter": "+1/+1", "amount": 2, "to": "self" } }] } }
```

**Start your engines! and max speed** (CR 702.178, 702.179). `"keywords": ["start_your_engines"]`
gives its controller speed 1 if they have none; the speed then rises by 1 (to at most 4) once on
each of their turns when an opponent loses life, as a triggered ability with no source. "Max speed —
[ability]" is `{ "max_speed": { "keywords": [...], "abilities": [...] } }`: any kind of ability, which
the object has only while its controller's speed is 4 (a card in the graveyard: its owner's).
"Your speed" is the amount `{ "speed": "you" }`; "as long as you have max speed" is the condition
`{ "max_speed": true }`.

```json
{ "name": "Example Racer", "mana_cost": "{1}{R}", "types": ["creature"], "subtypes": ["goblin", "pilot"],
  "power": 2, "toughness": 2, "keywords": ["start_your_engines"],
  "abilities": [{ "max_speed": { "keywords": ["double_strike"] } },
                { "max_speed": { "abilities": [
                  { "activated": { "cost": [{ "mana": "{2}" }, "exile_self_from_graveyard"],
                                   "effects": [{ "draw": { "amount": 1 } }] } }] } }] }
```

### 4.17 Cards with faces: double-faced, Adventure, Omen and prepare cards

A card with more than one set of characteristics has `layout` and `faces` instead of the
top-level fields of section 2. Each face is a complete card block (its own `name`,
`mana_cost`, `types`, `abilities`, …), front face first. A top-level `name` is optional;
if given, it must be the faces' names joined by `" // "`. The card id comes from the front
face's name (`"Alfa // Bravo"` → `alfa`), so decks may name it either way.

| `layout` | Cards | Rules |
| --- | --- | --- |
| `transform` | nonmodal double-faced cards: cast and played front face up; they transform or enter transformed | CR 712.2, 701.27 |
| `modal` | modal double-faced cards: choose the face to cast or play (a modal card can also transform) | CR 712.3, 712.8b, 712.9 |
| `adventure` | adventurer cards: `faces[1]` is the Adventure (instant or sorcery with the subtype `adventure`) | CR 716 |
| `omen` | omen cards: `faces[1]` is the Omen (instant or sorcery with the subtype `omen`) | CR 721 |
| `prepare` | preparation cards: `faces[1]` is the prepare spell (an instant or sorcery) | CR 723 |

Outside the battlefield and stack a card has only its front face's characteristics
(CR 712.6a, 716.4, 721.4); a game object shows the face that's up by its `card`: the card
id for the front face, `"<card id>/1"` while the back face (or the Adventure or Omen on
the stack) is up. A copy of a permanent copies the face that's up (CR 707.8).

| Oracle words | Data |
| --- | --- |
| "Transform this creature." | `{ "transform": {} }` (`to`: any selector; default `"self"`) |
| "Whenever this creature transforms into [this face]" | `{ "triggered": { "when": { "transforms": {} }, … } }` on that face |
| "When this creature enters or transforms into [this face]" | `"when": { "any_of": [{ "enters": {} }, { "transforms": {} }] }` |
| "exile it, then return it to the battlefield transformed" | `exile`, then `{ "return_to_battlefield": { "to": { "result": 0 }, "transformed": true } }` |
| "if this creature is transformed" / "transformed permanents you control" | filter `{ "creature": { "transformed": true } }` |
| "This creature enters prepared." | the ability `"enters_prepared"` |
| "… this creature becomes prepared." / "becomes unprepared" | `{ "prepare": {} }` / `{ "unprepare": {} }` |
| "if this creature isn't prepared" | `"if": { "source": { "creature": { "prepared": false } } }` |

Casting another face is a priority option with `face`: `{type: "cast", object: id,
face: 1}` casts a modal card's back face, an Adventure or an Omen from the hand, and
`{type: "play_land", object: id, face: 1}` plays a modal card's land face. An Adventure
that resolves is exiled, and its owner may play the card from exile (not as an Adventure);
an Omen that resolves is shuffled into its owner's library. A permanent that becomes
prepared gives its controller a copy of its prepare spell in exile, which they may cast
until the permanent stops being prepared; casting it unprepares the permanent.

```json
{ "name": "Example Squire // Example Reaver", "layout": "transform", "faces": [
  { "name": "Example Squire", "mana_cost": "{1}{W}", "types": ["creature"], "power": 2, "toughness": 2,
    "abilities": [{ "activated": { "cost": [{ "mana": "{3}" }], "timing": "sorcery", "effects": [{ "transform": {} }] } }] },
  { "name": "Example Reaver", "colors": ["W"], "types": ["creature"], "keywords": ["lifelink"], "power": 3, "toughness": 3,
    "abilities": [{ "triggered": { "when": { "transforms": {} }, "effects": [{ "draw": { "amount": 1 } }] } }] }
] }
```

```json
{ "name": "Example Knight // Example Errand", "layout": "adventure", "faces": [
  { "name": "Example Knight", "mana_cost": "{2}{G}", "types": ["creature"], "power": 3, "toughness": 2 },
  { "name": "Example Errand", "mana_cost": "{1}{G}", "types": ["sorcery"], "subtypes": ["adventure"],
    "abilities": [{ "spell": { "effects": [{ "gain_life": { "amount": 3 } }] } }] }
] }
```

```json
{ "name": "Example Scholar // Example Notes", "layout": "prepare", "faces": [
  { "name": "Example Scholar", "mana_cost": "{1}{U}", "types": ["creature"], "power": 1, "toughness": 3,
    "abilities": ["enters_prepared"] },
  { "name": "Example Notes", "mana_cost": "{U}", "types": ["sorcery"],
    "abilities": [{ "spell": { "effects": [{ "draw": { "amount": 1 } }] } }] }
] }
```

Not yet: casting another face from outside the hand, casting a card transformed, the mana
value of a back face (CR 202.3b), day/night (CR 702.145), meld (CR 713), convert
(CR 701.28) and an "as this enters" choice on a modal card's land face.

### 4.18 Mana spent to cast a spell (converge)

The mana paid for a spell is recorded by type as it is paid (CR 601.2h), and the permanent the
spell becomes keeps it (CR 400.7d). The amount `mana_spent` reads it:

| Oracle words | Data |
| --- | --- |
| "the amount of mana spent to cast this spell / this creature" | `{ "mana_spent": {} }` |
| converge: "the number of colors of mana spent to cast it" | `{ "mana_spent": { "colors": true } }` (colorless isn't a color) |
| "if {W}{W} was spent to cast it" | `{ "amount": { "mana_spent": { "color": "W" } }, "at_least": 2 }` |
| "whenever you cast a spell, if four or more mana was spent to cast it" | trigger `if`: `{ "amount": { "mana_spent": { "of": { "triggering": "object" } } }, "at_least": 4 }` |
| "the amount of mana spent to cast target spell" | `{ "mana_spent": { "of": { "target": 0 } } }` |
| "enters with a +1/+1 counter for each color of mana spent to cast it" | `{ "enters_with_counters": { "counters": { "+1/+1": { "mana_spent": { "colors": true } } } } }` |

A trigger's `if` is checked as it triggers with the event it's about (CR 603.4), so "that
spell" works there. Nothing was spent on a permanent that wasn't cast, and a copy of a spell
had no mana spent on it (CR 707.10).

```json
{ "name": "Example Prism Archaic", "mana_cost": "{4}{G}", "types": ["creature"], "subtypes": ["avatar"],
  "power": 1, "toughness": 1,
  "abilities": [{ "enters_with_counters": { "counters": { "+1/+1": { "mana_spent": { "colors": true } } } } },
                { "triggered": { "when": { "enters": {} }, "if": { "amount": { "mana_spent": { "color": "G" } }, "at_least": 2 },
                                 "effects": [{ "draw": { "amount": 1 } }] } }] }
```

### 4.19 Keyword actions and keyword abilities of recent sets

Keyword *abilities* without a number go in `keywords`; those with a number are abilities
with an `amount` (any amount, e.g. `{ "power": "self" }` for "firebending X, where X is its
power"). Keyword *actions* are effects.

| Oracle text | Data |
| --- | --- |
| "Prowess" (CR 702.108) | `"keywords": ["prowess"]` (granted by `grant` too) |
| "Job select" on an Equipment (CR 702.182) | `"keywords": ["job_select"]` |
| "Mobilize 2" (CR 702.181) | ability `{ "mobilize": { "amount": 2 } }` |
| "Firebending 2" (CR 702.189) | ability `{ "firebending": { "amount": 2 } }` |
| "Kindred Sorcery — Goblin" (CR 308) | `"types": ["kindred", "sorcery"], "subtypes": ["goblin"]` |
| "As an additional cost to cast this spell, blight 1" (CR 701.68) | `{ "additional_cost": { "cost": [{ "blight": { "amount": 1 } }] } }`; also an activated ability's `cost` |
| "you may blight 2. If you do, draw a card" | `{ "may": { "effects": [{ "blight": { "amount": 2 } }], "then": [{ "draw": { "amount": 1 } }] } }` |
| "each opponent blights 1" | `{ "blight": { "amount": 1, "to": "each_opponent" } }` (the blighted creatures are its results) |
| "it connives" / "target creature you control connives 2" (CR 701.50) | `{ "connive": {} }` / `{ "connive": { "amount": 2, "to": { "target": 0 } } }` |
| "recruit" (CR 701.70) | `{ "recruit": {} }` |
| "amass Orcs 2" (CR 701.47) | `{ "amass": { "subtype": "orc", "amount": 2 } }` (the amassed Army is its result: "attach this Equipment to the amassed Army" is `attach` to `{ "result": n }`) |
| "empower Jace 2" (CR 701.71) | `{ "empower_jace": { "amount": 2 } }` |
| "it endures 2" (CR 701.63) | `{ "endure": { "amount": 2 } }` (a fixed number) |
| "create two 1/1 tokens tapped and attacking" | `create_token` with `"tapped": true, "attacking": true` |
| "add {R}{R}; until end of combat, you don't lose this mana" | `{ "add_mana": { "produce": "{R}{R}", "until": "end_of_combat" } }` |

```json
{ "name": "Example Ember Captain", "mana_cost": "{2}{R}", "types": ["creature"], "subtypes": ["human", "soldier"],
  "power": 2, "toughness": 2, "keywords": ["prowess"],
  "abilities": [{ "mobilize": { "amount": 1 } }, { "firebending": { "amount": { "power": "self" } } },
                { "triggered": { "when": { "enters": {} }, "effects": [{ "connive": {} }] } }] }
```

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

**Rejected with a path.** A typo or an unknown keyword:
```json
{ "name": "Gale Drifter", "mana_cost": "{2}{U}", "types": ["creature"], "keywords": ["flyng"], "power": 2, "toughness": 2 }
```
→ `keywords[0]: unknown keyword "flyng" (supported: …)`.

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

**Cards outside the game** (CR 400.11a). The engine plays single games, so a deck may
list the cards its player owns outside the game, a constructed sideboard, as
`outside`. These cards don't count toward the 60. There can be at most 15 of them,
and the four-copy limit counts the deck and the outside list together (CR 100.4a).
Errors carry a path, for example `outside[2].card: "Black Lotus" is not defined in cards`.

```json
{ "cards": [ ... ],
  "main":    [ { "card": "Forest", "count": 24 }, { "card": "Grizzly Bears", "count": 4 } ],
  "outside": [ { "card": "Hill Giant", "count": 2 } ] }
```

During a game these cards aren't objects (CR 400.11). Each player's list is
`state.players[i].outside`, a list of card ids that only that player sees in their
view. A `play_from` ability with `"outside"` among its zones offers them as
`{ "type": "cast", "object": "outside:hill_giant", "via": ... }` (or `play_land`). The
object is created as the card enters the game, and that player owns it (CR 108.3).

---

## 7. Validating

From the shell (exit code 0 means all valid, 1 means some invalid):

```sh
bundle exec exe/enjine --validate cards.json
```

`cards.json` is a JSON array of card blocks (or a single block). The report:

```json
{ "rules_version": "2026-11-06", "engine_version": "0.1.0",
  "valid":   [ { "index": 0, "id": "lightning_bolt", "name": "Lightning Bolt", "card": { ...canonical... } } ],
  "invalid": [ { "index": 1, "name": "Gale Drifter", "errors": ["keywords[0]: unknown keyword \"flyng\" ..."] } ] }
```

From Ruby:

```ruby
require "enjine"

begin
  defn = Enjine::CardDefinition.from_h(data)   # data: Hash parsed from JSON
  store(defn.id, defn.to_h)                    # canonical, round-trips exactly
rescue Enjine::InvalidCardDefinition => e
  warn e.errors                                # every problem, each with a path
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
```

When building a game, load the deck's rows from `enjine_cards` and pass their
`data` as the deck's `cards`.
