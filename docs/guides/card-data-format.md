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
| `mana_cost` | castable cards | string | `"{2}{W}{W}"`. Symbols: `{N}` generic, `{W}{U}{B}{R}{G}`, `{C}`, `{X}` (announced while casting; use the amount `"x"` in effects, see 4.7). Lands must **not** have one. A card without one can't be cast. Two-color hybrid `{R/G}` is supported (paid with either color, CR 107.4e), and so is monocolored hybrid `{2/B}` (one black mana or two mana of any type; mana value 2, CR 202.3f); Phyrexian and `{S}` are not yet. |
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
| "As this land enters, choose a color. {T}: Add one mana of the chosen color." | `{ "choose_color": {} }`, `{ "mana": { "cost": ["tap"], "color": "chosen" } }` (also on `add_mana`, CR 607.2d) |
| "{T}, Pay 1 life: Add one mana of any color." | `{ "mana": { "cost": ["tap", { "pay_life": 1 }], "color": "any_one" } }` |
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
  cost; `"sacrifice"` sacrifices this permanent and `"exile_self"` exiles it; `{ "sacrifice_permanent": { "filter": "creature", "other": true } }`,
  `{ "tap_permanents": { "count": 3, "filter": ... } }` and `{ "remove_counters": { "count": 3 } }` are chosen while
  activating; `"exile_self_from_graveyard"` / `"bottom_self_from_graveyard"` make it a graveyard ability. `{Q}` is
  not supported yet. More costs (each also usable in a spell's `additional_cost`):

  | Oracle words | Cost |
  | --- | --- |
  | "Discard a card" / "Discard two cards" / "Discard a land card" | `"discard"` / `{ "discard": { "count": 2 } }` / `{ "discard": { "card": { "types": ["land"] } } }` |
  | "Discard a card at random" | `{ "discard": { "random": true } }` (CR 701.9b) |
  | "Exile two cards from your graveyard" / "Exile a creature card from your graveyard" | `{ "exile_from_graveyard": { "count": 2 } }` / `{ "exile_from_graveyard": { "card": { "types": ["creature"] } } }` |
  | "Pay 2 life" / "Pay X life" | `{ "pay_life": 2 }` / `{ "pay_life": "X" }` (X announced, at most your life; CR 119.4) |
  | "Behold a Goblin" / "behold a Kithkin and exile it" | `{ "behold": { "card": { "subtypes": ["goblin"] } } }` / add `"exile": true` (the card is then `exiled_with` it, also after it leaves; CR 701.4) |

  ```json
  { "name": "Example Banner Champion", "mana_cost": "{2}{W}", "types": ["creature"], "subtypes": ["kithkin"],
    "power": 4, "toughness": 4,
    "abilities": [
      { "additional_cost": { "cost": [{ "behold": { "card": { "subtypes": ["kithkin"] }, "exile": true } }] } },
      { "triggered": { "when": { "leaves_battlefield": {} },
                       "effects": [{ "return_to_hand": { "to": "exiled_with" } }] } }] }
  ```

  "You may behold a Dragon. If you do, …" is the effect `behold` under `may`:
  `{ "may": { "effects": [{ "behold": { "card": { "subtypes": ["dragon"] } } }], "then": [...] } }`.
- `limit: "once_each_turn"`, `limit: "once"`, `only_if: condition`, `timing: "your_turn"`: "Activate only once each
  turn / only once / only if … / only during your turn" (CR 602.5b; "only once" lasts as long as the object).
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

`cost` is the signed number: `+1` → `1`, `−2` → `-2`, `0` → `0`, or `"-X"` (X is announced as
it's activated, at most the planeswalker's loyalty; effects read it as `"x"`). Sorcery timing and
once-per-turn are automatic. A static grants one like any other ability: "Planeswalkers you control
have '[−2]: …'" is `{ "static": { "affects": { "each": "planeswalker", "controller": "you" },
"abilities": [{ "loyalty": { "cost": -2, "effects": [ … ] } }] } }`.

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
| `"self"` | "this creature" / the card's own name, on a permanent; "this card" for an ability that works from a graveyard, exile or a hand ("{4}{B}: Return this card from your graveyard to the battlefield tapped") |
| `"attached"` | "equipped creature" / "enchanted creature", on an Equipment or Aura |
| `{ "each": "creature", "controller": "you" }` | "creatures you control", "each creature you control" |
| `{ "each": "creature", "controller": "opponent" }` | "creatures your opponents control" |
| `{ "each": "creature" }` | "each creature", "all creatures" |
| `{ "result": 0 }` | "it" / "that card" / "the token": what effect 0 of the same list moved or created (CR 400.7j) |
| `"gift_recipient"` | "the chosen player" of a gift (CR 702.174a; see 4.24) |

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
| "Whenever an opponent activates a loyalty ability" | `{ "activates_ability": { "controller": "opponent", "loyalty": true } }` |
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
| "If a triggered ability of an Ally you control triggers, it triggers an additional time" | `{ "additional_triggers": { "of": { "creature": { "subtypes": ["ally"] } } } }` (`"other": true`, `"subtypes": "chosen"` work in the filter; combine with `cause`) |
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
| `grant`, `become` | "gain flying until your next turn", "until your next turn, it becomes a land" | `"duration": "until_your_next_turn"` on `grant` or `become` |
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
| "Dragon spells you cast cost {1} less" / "Red spells you cast cost {1} less" | `{ "cost_modifier": { "spells": { "subtypes": ["dragon"] }, "reduce": 1 } }` / `"spells": { "colors": ["R"] }` (combine with `any_of` / `not`) |
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
  {1} or one mana of its color. **Improvise** (CR 702.126) is the keyword `"improvise"`:
  `{type: "improvise", object: id}` taps an untapped artifact you control to pay {1} of
  the generic part.

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
| "cards in your library", "half their library, rounded up" | `{ "library_size": "you" }`, `{ "divide": [{ "plus": [{ "library_size": <player> }, 1] }, 2] }` |
| "the greatest mana value among …" | `{ "greatest_mana_value": <selector> }` (0 for none) |
| "its mana value" / "its power" of a target destroyed earlier in the same effects; "the sacrificed creature's power" after a `sacrifice_choice` | `{ "mana_value": { "target": 0 } }`, `{ "power": { "result": n } }`: read as it last existed on the battlefield (CR 608.2h) |
| "the sacrificed artifact's mana value" when the sacrifice is a cost | `{ "sacrificed": "mana_value" }` (also `"power"`, `"toughness"`; CR 601.2h) |
| delirium: "four or more card types among cards in your graveyard" | `{ "amount": { "card_types": { "each": { "graveyard_card": {} }, "controller": "you" } }, "at_least": 4 }` |
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
| target opponent reveals their hand; you choose a [quality] card from it; that player discards that card | `{ "choose_cards": { "from": { "hand": { "target": 0 } }, "for": spec, "reveal": "all", "put": "discard" } }` (a discard: discard triggers see it) |
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
| "it endures 2" (CR 701.63) | `{ "endure": { "amount": 2 } }` (any amount, see 4.24) |
| "create two 1/1 tokens tapped and attacking" | `create_token` with `"tapped": true, "attacking": true` |
| "add {R}{R}; until end of combat, you don't lose this mana" | `{ "add_mana": { "produce": "{R}{R}", "until": "end_of_combat" } }` |
| "earthbend 2" (CR 701.66) | a target `{ "land": { "controller": "you" } }` and `{ "earthbend": { "amount": 2, "to": { "target": 0 } } }` (the land is its result: "that land becomes an Island" is `become` with `{ "result": n }`) |
| "Waterbend {3}: …" / "As an additional cost to cast this spell, waterbend {X}" (CR 701.67) | the cost `{ "waterbend": "{3}" }` in an activated ability's `cost`, an `additional_cost` (optional or not) or `kicker`; while paying, `{type: "waterbend", object: id}` taps an artifact or creature for {1} of it |
| "you may waterbend {4} as an additional cost … if this spell's additional cost was paid" | `{ "additional_cost": { "cost": [{ "waterbend": "{4}" }], "optional": true } }` and the condition `{ "cast_with": "additional_cost" }` (4.24) |
| "discard a card unless you waterbend {2}" / "Ward—Waterbend {4}" | `{ "pay": { "waterbend": "{2}", "otherwise": [{ "discard": { "amount": 1, "to": "you" } }] } }` / `{ "ward": { "waterbend": "{4}" } }` (also `counter_unless_pays`) |
| "airbend target creature or spell" (CR 701.65) | `{ "airbend": { "to": { "target": 0 } } }` (the owner may cast each exiled card for {2} while it stays exiled) |
| "Whenever you waterbend, earthbend, firebend, or airbend" | `{ "any_of": [{ "waterbends": {} }, { "earthbends": {} }, { "firebends": {} }, { "airbends": {} }] }` |
| "Saddle 2" (CR 702.171) / "becomes saddled until end of turn" | ability `{ "saddle": { "power": 2 } }` / effect `{ "become_saddled": { "to": … } }` |
| "Whenever this creature attacks while saddled" | `"when": { "attacks": {} }, "while": { "source": { "creature": { "saddled": true } } }` (filters take `"saddled"`) |
| "Whenever this creature becomes saddled" / "saddles a Mount" | `{ "becomes_saddled": {} }` / `{ "saddles_mount": {} }` (`{ "triggering": "object" }` is the Mount) |
| "{W}, {T}, Exert this creature: …" (CR 701.43) | the cost `"exert"`: it doesn't untap during your next untap step |
| "Decayed" (CR 702.147), "Wither" (CR 702.80) | `"keywords": ["decayed"]` (a `decayed` counter gives it too), `"keywords": ["wither"]` |

```json
{ "name": "Example Ember Captain", "mana_cost": "{2}{R}", "types": ["creature"], "subtypes": ["human", "soldier"],
  "power": 2, "toughness": 2, "keywords": ["prowess"],
  "abilities": [{ "mobilize": { "amount": 1 } }, { "firebending": { "amount": { "power": "self" } } },
                { "triggered": { "when": { "enters": {} }, "effects": [{ "connive": {} }] } }] }
```

```json
{ "name": "Example Stone Monk", "mana_cost": "{2}{G}", "types": ["creature"], "subtypes": ["human", "monk", "mount"],
  "power": 2, "toughness": 2,
  "abilities": [{ "triggered": { "when": { "enters": {} }, "targets": [{ "land": { "controller": "you" } }],
                                 "effects": [{ "earthbend": { "amount": 2, "to": { "target": 0 } } }] } },
                { "activated": { "cost": [{ "waterbend": "{3}" }], "effects": [{ "draw": { "amount": 1 } }] } },
                { "saddle": { "power": 1 } }] }
```

### 4.20 Set mechanics: power-up, teamwork, tiered, Class cards, increment, extort, riot, storm, cascade, boast, storied, colors among, domain

| Oracle text | Data |
| --- | --- |
| "Power-up — {5}{U}: …" (CR 702.193) | `{ "activated": { "power_up": true, "cost": [{ "mana": "{5}{U}" }], "effects": [...] } }`: activate only once; the turn the permanent entered, the cost is reduced by its mana cost (colored mana by the same color, the excess and generic by generic, CR 118.7) |
| "Boast — {1}{R}: …" (CR 702.142) | `"boast": true` on the activated ability: only if this creature attacked this turn, once each turn |
| "Teamwork 4" (CR 702.194) | ability `{ "teamwork": { "power": 4 } }`: announced like kicker (`choose_kicker`), then one `choose_cost` per creature tapped until their total power is 4 or more |
| "if this spell was cast using teamwork" | condition `{ "cast_with": "teamwork" }`; "choose both instead" is `"choose_if": { "if": { "cast_with": "teamwork" }, "choose": 2 }`; targets only with teamwork are `kicked_targets` |
| "Increment" (CR 702.191) | `"keywords": ["increment"]` |
| "Riot" (CR 702.136) | `"keywords": ["riot"]`: an `enter_choice` of `{type: "option", option: "counter"}` (an additional +1/+1 counter) or `"haste"` (it can't have another "as this enters" choice) |
| "Storm" (CR 702.40), "Cascade" (CR 702.85) | `"keywords": ["storm"]`, `"keywords": ["cascade"]`; a cast trigger's "that many" (`{ "triggering": "amount" }`) is the number of spells cast before that spell this turn |
| "Extort" (CR 702.101) | `"keywords": ["extort"]` (a `pay` {W/B} choice as it resolves) |
| "the number of colors among permanents you control" (CR 105.2) | amount `{ "distinct_colors": { "each": "permanent", "controller": "you" } }` |
| domain: "the number of basic land types among lands you control" (CR 305.6) | amount `{ "distinct_land_types": { "each": "land", "controller": "you" } }` |
| "Tiered" (CR 702.183): "• Fira — {2} — …" | a modal `spell` with `"choose": 1` whose modes each have a `cost`: `{ "cost": "{2}", "effects": [...] }`; the chosen mode's cost is paid in addition (modes the player can't pay for aren't offered) |
| Class cards (CR 717): "{1}{R}: Level 2 — [abilities]" | `"subtypes": ["class"]` and one ability per level bar: `{ "class_level": { "level": 2, "cost": "{1}{R}", "abilities": [...], "keywords": [...] } }`; the abilities above the first bar are ordinary abilities. Gaining a level is activated as a sorcery, only from the level below; a permanent without a level is level 1 |
| "When this Class becomes level 3" | trigger `{ "becomes_level": { "level": 3 } }` (listed in that level's `abilities`) |
| "Storied" (CR 702.195) | `"keywords": ["storied"]`: once you control it and three or more artifacts, Sagas and/or legendary permanents, you have an enduring story for the rest of the game (the player view's `designations`) |
| "as long as you have an enduring story" | condition `{ "designation": "enduring_story" }` (a static's or trigger's `if`, an activated ability's `only_if`) |

```json
{ "name": "Example Gamma Brawler", "mana_cost": "{1}{W}", "types": ["creature"], "power": 2, "toughness": 1,
  "keywords": ["increment"],
  "abilities": [{ "activated": { "power_up": true, "cost": [{ "mana": "{4}{W}" }],
                                 "effects": [{ "add_counters": { "counter": "+1/+1", "amount": 2, "to": "self" } }] } }] }
```

### 4.21 Rules-changing effects: losing abilities, restrictions, protection

**Losing all abilities** (CR 613.1f). `"loses_abilities": true` on a `become` effect or a `static`
ability. Layer 6 applies in timestamp order (CR 613.7): the permanent loses what it had, and
keeps abilities granted later and keyword counters put on it later. A permanent that loses its
abilities loses its static abilities' effects on others too (CR 613.8a), its characteristic-defining
power and toughness, and its "when this dies" abilities. A `static` can also set `colors` (layer 5)
and `base_power_toughness` (layer 7b); its `abilities` may be activated abilities, as `become`'s may.

| Oracle words | Data |
| --- | --- |
| "Target creature loses all abilities until end of turn" | `{ "become": { "loses_abilities": true, "to": { "target": 0 } } }` |
| "… loses all abilities for as long as this creature remains on the battlefield" | `become` with `"duration": "while_source_on_battlefield"` (does nothing if this has already left, CR 611.2b) |
| "Enchanted creature loses all abilities and is a black Skeleton with base power and toughness 1/1" | `{ "static": { "affects": "attached", "loses_abilities": true, "colors": ["B"], "creature_types": ["skeleton"], "base_power_toughness": { "power": 1, "toughness": 1 } } }` |
| "Other creatures you control have '{1}: This creature gets +1/+0 until end of turn'" | `static` with `"abilities": [{ "activated": … }]` (`self` is the creature that has it) |
| "This creature is the chosen type in addition to its other types" | `{ "choose_creature_type": {} }` and `{ "static": { "affects": "self", "subtypes": "chosen" } }` |
| "As this land enters, choose a basic land type. This land is the chosen type." | `{ "choose_basic_land_type": {} }` and the same `static` (a land with a basic land type has its mana ability, CR 305.6) |

```json
{ "name": "Example Fishbowl", "mana_cost": "{1}{U}", "types": ["enchantment"], "subtypes": ["aura"],
  "keywords": ["flash"],
  "abilities": [{ "enchant": "creature" },
                { "static": { "affects": "attached", "loses_abilities": true, "colors": ["U"],
                              "creature_types": ["fish"], "base_power_toughness": { "power": 1, "toughness": 1 } } }] }
```

**Restrictions on players and the game** (CR 101.2: a "can't" beats any "can"). They are
`player_rule` abilities (static, with an optional `if` condition seen from the source) or
`player_rule` effects (for a duration), with `affects` / `to` naming the players:

| Oracle words | Data |
| --- | --- |
| "Your opponents can't cast spells during your turn" | `{ "player_rule": { "rule": "cant_cast", "affects": "opponents", "if": { "your_turn": true } } }` |
| "Players can't cast spells this turn" | effect `{ "player_rule": { "rule": "cant_cast", "to": { "each": "player" } } }` |
| "… can't cast spells from anywhere other than their hands" | rule `cant_cast_except_from_hand` |
| "Creature spells you control can't be countered" | `{ "player_rule": { "rule": "spells_cant_be_countered", "spells": { "types": ["creature"] } } }` (`spells`: a card spec; also on `cant_cast`) |
| "Players can't gain life" | `{ "player_rule": { "rule": "cant_gain_life", "affects": "each" } }` |
| "Activated abilities of creatures can't be activated unless they're mana abilities" | `{ "player_rule": { "rule": "cant_activate", "affects": "each", "filter": "creature" } }` |
| "Damage can't be prevented (this turn)" / "Combat damage can't be prevented" | rule `damage_cant_be_prevented` / `combat_damage_cant_be_prevented` (game-wide, CR 615.12) |

```json
{ "name": "Example Hush Captain", "mana_cost": "{1}{W}", "types": ["creature"], "subtypes": ["human"],
  "power": 2, "toughness": 2,
  "abilities": [{ "player_rule": { "rule": "cant_cast", "affects": "opponents", "if": { "your_turn": true } } },
                { "player_rule": { "rule": "cant_gain_life", "affects": "opponents" } }] }
```

**Life totals, exchanges and player counters** (CR 119.5, 701.12, 122.1).

| Oracle words | Data |
| --- | --- |
| "Your life total becomes 10" | `{ "set_life": { "amount": 10 } }` (gains or loses the difference) |
| "Exchange life totals with target opponent. If you lost life this way, draw that many cards" | `{ "exchange_life_totals": { "with": { "target": 0 } } }`, then `{ "draw": { "amount": { "this_way": 0 } } }` |
| "Gain control of target creature for as long as this creature remains on the battlefield" | `{ "gain_control": { "to": { "target": 0 }, "duration": "while_source_on_battlefield" } }` (also `while_source_tapped`; control goes back as it ends, CR 611.2b) |
| "Exchange control of target creature you control and target creature an opponent controls" | `{ "exchange_control": { "to": { "target": 0 }, "with": { "target": 1 } } }` |
| "that player gets two poison counters" / "you get an experience counter" | `{ "add_counters": { "counter": "poison", "amount": 2, "to": { "triggering": "player" } } }` / `"counter": "experience", "to": "you"` |
| "the number of experience counters you have" | amount `{ "counters": { "of": "you", "kind": "experience" } }` |
| "Target opponent skips their next turn" | `{ "skip_turns": { "amount": 1, "to": { "target": 0 } } }` (CR 614.10; skips add up) |

A player with ten or more poison counters loses the game (CR 704.5c). An exchange that can't be
completed doesn't happen at all (CR 701.12a).

```json
{ "name": "Example Venom Adder", "mana_cost": "{1}{G}", "types": ["creature"], "subtypes": ["snake"],
  "power": 1, "toughness": 2, "keywords": ["deathtouch"],
  "abilities": [{ "triggered": { "when": { "deals_damage": { "combat": true, "to": "player" } },
                                 "effects": [{ "add_counters": { "counter": "poison", "amount": 2,
                                                                 "to": { "triggering": "player" } } }] } }] }
```

**Emblems** (CR 114). "You get an emblem with '…'" is `create_emblem` with the emblem's
`abilities` (triggered, static or player_rule). The emblem goes to the command zone for the rest
of the game and its abilities work from there; "this emblem" is the source of what they do. The
game view lists emblems under `command`.

```json
{ "loyalty": { "cost": -7, "effects": [
  { "create_emblem": { "abilities": [
    { "triggered": { "when": { "cast": {} }, "targets": ["any_target"],
                     "effects": [{ "deal_damage": { "amount": 5, "to": { "target": 0 } } }] } }] } }] } }
```

**Hexproof from and protection from a quality** (CR 702.11d, 702.16). Abilities whose value is a
card spec of the quality, matched against the spell, or the source of the ability or damage, as it
is now: `{ "colors": ["B"] }` (any of those colors), `{ "types": ["instant"] }`,
`{ "color_count": { "equal": 1 } }` (monocolored; `at_least: 2` multicolored). "From A and from B"
is two abilities. Protection also prevents damage from such sources, stops such creatures from
blocking it and such Auras and Equipment from staying attached (CR 704.5m-n). `"protection_from":
"everything"` is protection from everything. Both may be granted by `static` and `become` `abilities`.

```json
{ "name": "Example Ward Knight", "mana_cost": "{1}{W}", "types": ["creature"], "subtypes": ["human", "knight"],
  "power": 2, "toughness": 2,
  "abilities": [{ "hexproof_from": { "colors": ["B"] } }, { "protection_from": { "colors": ["R"] } }] }
```

### 4.22 Damage and combat rules

A damage replacement or prevention ability names the damage it watches with `by` (sources) and `to`
(recipients), both optional: `"self"`, `"attached"` or `{ "each": filter, "controller": "you" | "opponent" |
"any", "other": bool }`. `each` is optional and players match too, so `{ "controller": "opponent" }` is "an
opponent or a permanent an opponent controls". `combat` is `"combat"` or `"noncombat"`.

| Oracle text | Data |
| --- | --- |
| "If a source you control would deal damage to an opponent or a permanent an opponent controls, it deals double that damage instead" | `{ "damage_replacement": { "by": { "controller": "you" }, "to": { "controller": "opponent" }, "multiply": 2 } }` |
| "... noncombat damage ..., it deals that much damage plus 1 instead" | same with `"combat": "noncombat", "plus": 1` (`plus` is an amount) |
| "All damage that would be dealt to you and other permanents you control is dealt to this creature instead" | `{ "damage_replacement": { "to": { "controller": "you", "other": true }, "redirect": "self" } }` |
| "Prevent all combat damage that would be dealt to and dealt by this creature" | two abilities: `{ "prevent_damage": { "to": "self", "combat": "combat" } }` and the same with `"by": "self"` |
| "Damage can't be prevented" / "... this turn" | ability `"damage_unpreventable"` / effect `"damage_unpreventable"` |
| "Prevent the next 3 damage that would be dealt to any target this turn" | effect `{ "prevent_damage": { "to": { "target": 0 }, "next": 3 } }` (`by` instead of or with `to`: "dealt by target creature") |
| "Whenever this creature is dealt damage" / "Whenever an opponent is dealt noncombat damage" | trigger `{ "dealt_damage": {} }` / `{ "dealt_damage": { "player": "opponent", "noncombat": true } }` ("that much" is `{ "triggering": "amount" }`) |
| "Whenever a source you control deals noncombat damage to an opponent" | trigger `{ "deals_damage": { "subject": { "each": "permanent", "controller": "you" }, "noncombat": true, "to": "opponent" } }` |
| "if an opponent was dealt noncombat damage this turn" | `{ "amount": { "noncombat_damage_this_turn": "each_opponent" }, "at_least": 1 }` |
| "Whenever this creature blocks a creature with flying" | trigger `{ "blocks": { "blocking": { "creature": { "keywords": ["flying"] } } } }` |
| "If excess damage was dealt this way" / "equal to the excess damage" | `{ "this_way": n }` of the `deal_damage` effect n |
| "This creature must be blocked if able" | `"keywords": ["must_be_blocked"]` |
| "assigns combat damage equal to its toughness rather than its power" (when greater) | `"keywords": ["assigns_damage_by_toughness"]`, or a `static`/`grant` handing it out |
| "After this phase, there is an additional combat phase [followed by an additional main phase]" | `{ "additional_phases": { "phases": ["combat", "main"] } }`; "if it's the first combat phase of the turn" is `{ "first_combat_phase": true }` |
| "If a creature an opponent controls would die, exile it instead" | `{ "exile_if_dies": { "affects": { "each": "creature", "controller": "opponent" } } }` |
| "If one or more tokens would be created under your control, twice that many ... instead" | `"double_tokens"` |

```json
{ "name": "Example Pyre Warden", "mana_cost": "{2}{R}{W}", "types": ["creature"], "subtypes": ["human", "wizard"],
  "power": 2, "toughness": 4,
  "abilities": [{ "damage_replacement": { "by": { "controller": "you" }, "to": { "controller": "opponent" },
                                          "combat": "noncombat", "plus": 1 } },
                { "prevent_damage": { "to": { "each": "creature", "controller": "you", "other": true }, "combat": "noncombat" } },
                { "triggered": { "when": { "dealt_damage": { "player": "opponent", "noncombat": true } },
                                 "effects": [{ "gain_life": { "amount": 1 } }] } }] }
```

### 4.23 Spell targets, cast zones, copying abilities, randomness and proliferate

| Oracle text | Data |
| --- | --- |
| "Whenever you cast a spell that targets a creature you control" (CR 603.2, 115.1) | `{ "cast": { "targets": { "creature": { "controller": "you" } } } }` (any target filter, matched relative to the source) |
| "Whenever you cast a spell that targets this creature" | `{ "cast": { "targets": "self" } }` |
| "Whenever you cast an instant or sorcery spell that targets an opponent or a creature an opponent controls" | `{ "cast": { "spell": "instant_or_sorcery", "targets": { "one_of": ["opponent", { "creature": { "controller": "opponent" } }] } } }` |
| "Whenever you cast a spell from anywhere other than your hand" / "from exile" (CR 601.2a) | `{ "cast": { "not_from": "hand" } }` / `{ "cast": { "from": "exile" } }` |
| "Spells you cast from anywhere other than your hand cost {1} less" | `{ "cost_modifier": { "not_from": "hand", "reduce": 1 } }` (`from` works too) |
| "Copy target activated or triggered ability you control [from a creature source]. You may choose new targets for the copy." (CR 707.10) | target `{ "stack_ability": { "controller": "you", "source": "creature" } }`, effect `{ "copy_spell": { "of": { "target": 0 }, "new_targets": true } }` (the copy has the same source, CR 707.10b) |
| "discard a card at random" (CR 701.9b) | `{ "discard": { "amount": 1, "random": true } }` |
| "exile a card from your graveyard at random" | `{ "choose_cards": { "from": { "graveyard": "you" }, "for": { "permanent": true }, "put": "exile", "random": true } }` |
| "Flip a coin. If you win the flip, …" (CR 705.2) | `{ "flip_coins": {} }`, then the effect with `"if": { "amount": { "this_way": 0 }, "at_least": 1 }` (you call the flip: a decision) |
| "Flip five coins. … X, where X is the number of coins that came up heads" | `{ "flip_coins": { "amount": 5, "count": "heads" } }`, X is `{ "this_way": 0 }` |
| "Proliferate" / "Proliferate X times" (CR 701.34a) | `{ "proliferate": {} }` / `{ "proliferate": { "amount": "x" } }` (permanents and players with counters: one more of each kind each already has) |

The game's random number generator makes every random choice, so a game replays identically from
its seed and decisions, and an exported game continues with the same results.

```json
{ "name": "Example Spell Duelist", "mana_cost": "{1}{W}", "types": ["creature"], "subtypes": ["human", "samurai"],
  "power": 2, "toughness": 2,
  "abilities": [{ "triggered": { "when": { "cast": { "targets": { "creature": { "controller": "you" } } } },
                                 "effects": [{ "add_counters": { "counter": "+1/+1", "amount": 1, "to": "self" } },
                                             { "scry": { "amount": 1 } }] } }] }
```

### 4.24 Choosing between costs, optional additional costs and paying costs while resolving

| Oracle text | Data |
| --- | --- |
| "As an additional cost to cast this spell, behold a Goblin or pay {2}" (CR 601.2b) | `{ "additional_cost": { "cost": [{ "one_of": [{ "behold": { "card": { "subtypes": ["goblin"] } } }, { "mana": "{2}" }] }] } }` |
| "… sacrifice a creature or pay {3}{B}", "… blight 1 or pay {3}", "… pay 5 life or pay {2}", "… exile two cards from your graveyard or pay {1}{W}" | the same, with any two or more costs in the `one_of` |
| "{3}, {T}, Sacrifice an artifact or discard a nonland card: …" (CR 602.2b) | `"cost": [{ "mana": "{3}" }, "tap", { "one_of": [{ "sacrifice_permanent": { "filter": "artifact" } }, { "discard": { "card": { "not_types": ["land"] } } }] }]` |
| "As an additional cost to cast this spell, you may behold a Dragon. … If a Dragon was beheld, …" (CR 118.8b) | `{ "additional_cost": { "cost": [{ "behold": { "card": { "subtypes": ["dragon"] } } }], "optional": true } }` and the condition `{ "cast_with": "additional_cost" }` |
| "You may sacrifice an artifact or discard a card. If you do, draw a card." (CR 118.12) | `{ "pay": { "cost": [{ "one_of": [{ "sacrifice_permanent": { "filter": "artifact" } }, "discard"] }], "then": [{ "draw": { "amount": 1 } }] } }` |
| "… When you do, it deals 2 damage to any target" | `then`: `[{ "reflexive_trigger": { "targets": ["any_target"], "effects": [ … ] } }]` |
| "Ward—Pay 2 life", "Ward—Discard a card", "Ward—Discard a card or pay {2}" (CR 702.21a) | `{ "ward": { "cost": [{ "pay_life": 2 }] } }`, `[ "discard" ]`, `[{ "one_of": ["discard", { "mana": "{2}" }] }]` |
| "Ward—Get five poison counters" | `{ "ward": { "cost": [{ "get_counters": { "counter": "poison", "amount": 5 } }] } }` |
| "Exile X artifact cards from your graveyard: … -X/-X" (CR 601.2b) | `{ "exile_from_graveyard": { "count": "X", "card": { "types": ["artifact"] } } }` in the `cost` (X is announced, at most the number of matching cards; also `discard`, `exile_from_hand`) and the amount `"x"` in effects |
| "As this land enters, you may behold a Jace. If you don't, this land enters tapped." (CR 614.12) | `{ "enters_tapped_unless_behold": { "card": { "subtypes": ["jace"] } } }` (the `enter_choice` option `{type: "behold", object: id}`) |
| "Gift a Treasure … Return target spell to its owner's hand. If the gift was promised, …" (CR 702.174) | `"gift"` in `abilities`; the gift as the spell's first effect, `{ "create_token": { "token": "Treasure", "to": "gift_recipient", "if": { "cast_with": "gift" } } }`, then the rest (on a permanent: an `enters` trigger with `"if": { "cast_with": "gift" }`) |
| "You may discard your hand. If you do, draw …" / "… Draw X cards, where X is the number of cards discarded this way" | `{ "may": { "effects": [{ "discard": { "hand": true } }], "then": [ … ] } }`; X is `{ "this_way": n }` of that effect (n: its position in the list) |
| "Noncreature spells you cast have improvise." (CR 702.126a) | `{ "spells_have": { "spells": { "not_types": ["creature"] }, "keywords": ["improvise"] } }` (convoke too) |
| "Counter target spell unless its controller pays {2}. If …, {4} instead" | two `counter_unless_pays` with opposite `if` conditions (`cost` takes a list of costs too) |

Which `one_of` option is paid is announced while casting or activating, after modes and before X
(the `choose_cost_option` decision, CR 601.2b); only options that could be paid are offered, and a
spell or ability is castable only if some option can be. An optional additional cost is announced
with the `choose_kicker` decision (a spell has at most one kicker-like optional cost). While
resolving, the payer picks one `pay` choice per way the costs could be paid, makes the costs'
choices (which card to discard), then pays any mana; cancelling the mana counts as not paying,
but cards already revealed for a behold or permanents tapped for a cost stay so.

```json
{ "name": "Example Toll Titan", "mana_cost": "{2}{B}", "types": ["creature"], "subtypes": ["giant"],
  "power": 5, "toughness": 5,
  "abilities": [{ "additional_cost": { "cost": [{ "one_of": ["discard", { "mana": "{2}" }] }] } },
                { "ward": { "cost": [{ "one_of": ["discard", { "mana": "{2}" }] }] } }] }
```

### 4.25 Casting and mana: divided damage, casting restrictions, where mana came from

| Oracle text | Data |
| --- | --- |
| "deals 3 damage divided as you choose among one, two, or three targets" (CR 601.2d) | targets `[{ "filter": "any_target", "count": 3, "optional": true }]`, `"divide": 3`, effect `{ "distribute_damage": {} }` (at least one target; each gets at least 1) |
| "deals X damage divided as you choose among any number of target creatures, where X is the number of lands you control" | `"count": "any"` with `"divide": { "count": { "each": "land", "controller": "you" } }` (an amount, computed as it's cast or put on the stack) |
| "When you do, it deals 7 damage divided as you choose among one or two targets" | `reflexive_trigger` takes `divide` too |
| "You can't cast this spell unless there are seven or more cards in your graveyard" (CR 601.3) | ability `{ "cast_restriction": { "only_if": { "amount": { "graveyard_size": "you" }, "at_least": 7 } } }` |
| "You can't cast this spell during your first, second, or third turns of the game" | `"only_if": { "any": [{ "not": { "your_turn": true } }, { "amount": { "turns_taken": "you" }, "at_least": 4 }] }` (`turns_taken`: turns the player has begun, this one included) |
| "if the amount of mana spent to cast that spell was less than its mana value" | `{ "amount": { "mana_spent": { "of": { "target": 0 } } }, "at_most": { "plus": [{ "mana_value": { "target": 0 } }, -1] } }` (bounds may be amounts; a spell countered by this one is read as it last existed, CR 608.2h) |
| "if mana from a Treasure was spent to cast it" | `{ "amount": { "mana_spent": { "of": { "triggering": "object" }, "from": { "subtypes": ["treasure"] } } }, "at_least": 1 }` |
| "costs {X} less to cast, where X is the greatest toughness among creatures you control" | `{ "cost_reduction": { "amount": { "greatest_toughness": { "each": "creature", "controller": "you" } } } }` |
| "Spend this mana only to cast a spell from anywhere other than your hand" / "only to cast spells from exile" | `"spend_only": { "not_from": "hand" }` / `{ "from": "exile" }` (also with `spells`) |
| "{T}: Add {G}{G}. Activate only if there is an Elf card in your graveyard." (CR 602.5b) | `{ "mana": { "cost": ["tap"], "produce": "{G}{G}", "only_if": condition } }` |
| "{1}: Add {B}, {G}, or {W}. Activate only once each turn." (CR 602.5b) | `{ "mana": { "cost": [{ "mana": "{1}" }], "color": "any_one", "colors": ["W", "B", "G"], "limit": "once_each_turn" } }` |
| "If that spell would be put into a graveyard, exile it instead" (CR 614.1a) | `"exile_instead": true` on `cast_free`, `cast` or `play_permission`; a card spec instead of `true` limits it ("if an instant or sorcery spell cast this way …": `{ "any_of": [{ "types": ["instant"] }, { "types": ["sorcery"] }] }`) |
| "you may cast it, and mana of any type can be spent to cast that spell" (while resolving) | `{ "cast": { "to": { "target": 0 }, "any_mana_type": true } }` |

Mana made by an artifact that isn't a land remembers its source's characteristics as it made the mana: pool
mana in the player's `pool_sources`, restricted mana in its entry's `from`. When the pool holds the same type both
from such a source and from another, paying offers `{type: "pay_mana", mana: "R", from: i}` (the remembered
one) beside plain `{type: "pay_mana", mana: "R"}` (the other one first). The amount `mana_value` (of a
selector) counts X on the stack (CR 202.3e).

```json
{ "name": "Example Hoard Drake", "mana_cost": "{3}{B}{R}", "types": ["creature"], "subtypes": ["dragon"],
  "power": 4, "toughness": 4,
  "abilities": [
    { "triggered": { "when": { "enters": {} }, "targets": [{ "filter": "any_target", "count": 2, "optional": true }],
                     "divide": 4, "effects": [{ "distribute_damage": {} }] } },
    { "triggered": { "when": { "cast": {} },
                     "if": { "amount": { "mana_spent": { "of": { "triggering": "object" }, "from": { "subtypes": ["treasure"] } } },
                             "at_least": 1 },
                     "effects": [{ "draw": { "amount": 1 } }] } }] }
```

### 4.26 More combat and damage: block and attack restrictions, prevention follow-ups, ending the turn

A `then` list on a prevention or dies-to-exile replacement happens right after it applies (CR 615.5,
614.1a). Its effects need no choice; they read `{ "triggering": "amount" }` (the damage prevented),
`"object"` (the damage source, or the card exiled instead) and `"player"` (that object's controller). A
"When you do, …" is a `reflexive_trigger` in the list (CR 603.12).

| Oracle text | Data |
| --- | --- |
| "This creature can block only creatures with flying" / "can't block non-Spirit creatures" (CR 509.1b) | `{ "can_block_only": { "filter": { "creature": { "keywords": ["flying"] } } } }` / `"filter": { "creature": { "subtypes": ["spirit"] } }` |
| "Whenever this creature attacks for the first time each turn" | trigger `{ "attacks": { "first_time_this_turn": true } }` |
| "Whenever you attack with creatures with total power 12 or greater for the first time each turn" | trigger `{ "player_attacks": { "attacking_power": { "at_least": 12 }, "first_time_this_turn": true } }` |
| "After this phase, there is an additional combat phase. Only land creatures can attack during that combat phase." (CR 508.1c) | `{ "additional_phases": { "phases": ["combat"], "attackers": { "creature": { "types": ["land"] } } } }` |
| "If a creature you control that entered this turn would deal damage, it deals twice that much damage instead" | `{ "damage_replacement": { "by": { "each": { "creature": { "entered_this_turn": true } }, "controller": "you" }, "multiply": 2 } }` |
| "Until your next turn, if a source would deal damage to that player or a permanent that player controls, it deals double that damage instead" | effect `{ "damage_replacement": { "to": { "triggering": "player" }, "permanents": true, "multiply": 2, "duration": "until_your_next_turn" } }` |
| "If damage would be dealt to this creature, prevent that damage and put that many +1/+1 counters on him" | `{ "prevent_damage": { "to": "self", "then": [{ "add_counters": { "counter": "+1/+1", "amount": { "triggering": "amount" }, "to": "self" } }] } }` |
| "The next time a source of your choice would deal damage to you this turn, prevent that damage. When damage is prevented this way, … deals that much damage to that source's controller" (CR 615.8, 609.7a) | effect `{ "prevent_damage": { "to": "you", "by": "chosen_source", "next_time": true, "then": [{ "reflexive_trigger": { "effects": [{ "deal_damage": { "amount": { "triggering": "amount" }, "to": { "triggering": "player" } } }] } }] } }` |
| "Prevent all damage that would be dealt by up to one target creature for as long as this Saga remains on the battlefield" (CR 611.2b) | effect `prevent_damage` with `"by": { "target": 0 }, "duration": "while_source_on_battlefield"` |
| "Prevent all damage that would be dealt to creatures you control this turn" (the creatures as damage is dealt, CR 611.2c) | effect `{ "prevent_damage": { "to_each": { "each": "creature", "controller": "you" } } }` |
| "Damage isn't removed from this creature during cleanup steps" (CR 514.2) | `"keywords": ["keeps_damage"]` |
| "If a creature an opponent controls would die, exile it instead. When you do, create a 2/2 Wolf" | `{ "exile_if_dies": { "affects": { … }, "then": [{ "reflexive_trigger": { "effects": [{ "create_token": … }] } }] } }` (the card is also "exiled with" this permanent: `"exiled_with"`) |
| "It fights target creature an opponent controls. When excess damage is dealt to the creature an opponent controls this way, …" (CR 120.4a) | `fight`, then `{ "reflexive_trigger": { "if": { "amount": { "this_way": 0 }, "at_least": 1 }, … } }` (a fight's `this_way` is the excess damage dealt to its `with` creature) |
| "End the turn." (CR 725.1) | `"end_the_turn"` (the spell's later effects don't happen) |

A source that left the zone it was in still deals damage with the deathtouch, lifelink and wither it had
(CR 702.2e, 702.15c, 702.80b).

```json
{ "name": "Example Sanctum Healer", "mana_cost": "{3}{W}{W}", "types": ["creature"], "subtypes": ["human", "cleric"],
  "power": 4, "toughness": 4,
  "abilities": [{ "prevent_damage": { "to": "self", "then": [{ "add_counters": { "counter": "+1/+1",
                                                                                 "amount": { "triggering": "amount" }, "to": "self" } }] } },
                { "triggered": { "when": { "attacks": { "first_time_this_turn": true } },
                                 "effects": [{ "additional_phases": { "phases": ["combat"] } }] } }] }
```

### 4.27 Names and card types set by statics, protection from opponents, crewing power, "for as long as you control"

| Oracle text | Data |
| --- | --- |
| "Enchanted creature loses all abilities and is a black Skeleton creature with base power and toughness 1/1" (it loses its other card types, CR 205.1a) | `static` with `"affects": "attached"`, `"loses_abilities": true`, `"colors": ["B"]`, `"set_types": ["creature"]`, `"creature_types": ["skeleton"]`, `"base_power_toughness": { "power": 1, "toughness": 1 }` |
| "… named Legitimate Businessperson" (CR 612.8, layer 3) | `"name": "Legitimate Businessperson"` on the same `static` (the legend rule and name filters see it) |
| "Enchanted permanent is a Construct creature with base power and toughness 5/5 in addition to its other types" | `static` with `"types": ["creature"]`, `"subtypes": ["construct"]`, `"base_power_toughness"` |
| "You have protection from each of your opponents" (CR 702.16k) | `{ "player_rule": { "rule": "protection_from_opponents" } }` (opponents' spells and abilities can't target you; damage from their sources is prevented) |
| "Protection from each of your opponents" on a permanent | `{ "protection_from": "each_opponent" }` (also grantable by `static` and `become`) |
| "Each other creature you control has hexproof from each of its colors" (CR 702.11g) | `static` granting `{ "hexproof_from": "its_colors" }` |
| "This creature saddles Mounts and crews Vehicles as though its power were 2 greater" | `{ "tapping_power": { "for": ["crew", "saddle"], "plus": 2 } }` |
| "… crews Vehicles using its toughness rather than its power" / "stations permanents using its toughness" when greater (CR 702.184c) | `"use": "toughness"` / `"use": "toughness_if_greater"` with `"for": ["station"]` (a `static` can grant it) |
| "Activated abilities of artifacts and creatures can't be activated" (mana abilities included) / "its activated abilities can't be activated" | `static` handing out the keyword `abilities_cant_be_activated` (`"affects": "attached"` for an Aura); `player_rule` `cant_activate` still exempts mana abilities |
| "Spells and abilities can't be countered" | two `player_rule`s, `spells_cant_be_countered` and `abilities_cant_be_countered`, with `"affects": "each"` |
| "Gain control of target creature for as long as you control this Vehicle" (CR 611.2b) | `gain_control` or `become` with `"duration": "while_you_control_source"` (ends when this leaves or changes control, and never starts if that has already happened) |
| "Equipped creature has '{1}, {T}: Tap target creature. Return Trusty Boomerang to its owner's hand.'" (CR 607.1a) | selector `"granter"`: the permanent whose `static` granted the ability (`{ "return_to_hand": { "to": "granter" } }`) |
| "As this land enters, choose a basic land type. Then you may pay 2 life. If you don't, it enters tapped." | `choose_basic_land_type` then `enters_tapped_unless_pay_life`: several "as this enters" choices are asked in printed order (CR 614.12) |

An Aura or Equipment gets a new timestamp each time it becomes attached, and a permanent each time it
transforms (CR 613.7e, 613.7g), so a static of an Equipment attached after "loses all abilities" still
grants its abilities.

```json
{ "name": "Example Witness Shroud", "mana_cost": "{U}", "types": ["enchantment"], "subtypes": ["aura"],
  "abilities": [{ "enchant": "creature" },
                { "static": { "affects": "attached", "loses_abilities": true, "set_types": ["creature"],
                              "creature_types": ["citizen"], "base_power_toughness": { "power": 1, "toughness": 1 },
                              "name": "Nobody in Particular" } }] }
```

### 4.28 Triggers, turn history and the stack: last turn, land plays, copying "that ability"

| Oracle text | Data |
| --- | --- |
| "if an opponent was dealt noncombat damage last turn" (whoever's turn it was) | `{ "amount": { "noncombat_damage_last_turn": "each_opponent" }, "at_least": 1 }` |
| "Whenever you play a land" / "… from anywhere other than your hand" / "from exile" (CR 305.1) | trigger `{ "plays_land": {} }` / `{ "plays_land": { "not_from": "hand" } }` / `{ "from": "exile" }` (`controller` as for `cast`) |
| "if you've played a land or cast a spell this turn from anywhere other than your hand" | `{ "amount": { "plus": [{ "lands_played_this_turn": { "by": "you", "not_from": "hand" } }, { "spells_cast_this_turn": { "by": "you", "not_from": "hand" } }] }, "at_least": 1 }` |
| "Whenever a permanent you control enters from exile" | `{ "enters": { "subject": { "each": "permanent", "controller": "you" }, "from": "exile" } }` |
| "you may exchange life totals with target opponent. If you lost life this way, draw that many cards" (CR 608.2c) | `[{ "may": { "effects": [{ "exchange_life_totals": { "with": { "target": 0 } } }] } }, { "draw": { "amount": { "this_way": 0 } } }]` (a `may` records what its effects did) |
| "two target nonland permanents that share a card type" (CR 701.12b) | second target `{ "filter": …, "distinct_from": [0], "shares_type_with": 0 }`; on resolution `"if": { "share_card_type": [{ "target": 0 }, { "target": 1 }] }` |
| "Whenever you cast a spell that targets one or more creatures, those creatures …" | trigger `{ "cast": { "targets": "creature" } }`, selector `{ "triggering": "targets" }` (the targets that matched) |
| "an instant or sorcery spell with a single target" | `{ "cast": { "spell": "instant_or_sorcery", "single_target": true } }` |
| "You may choose new targets for that spell" (CR 115.7d) | `{ "choose_new_targets": { "of": { "triggering": "object" } } }` (keep or replace each target) |
| "When you next activate an exhaust ability this turn, copy it" (CR 707.10) | `{ "delayed_trigger": { "when": { "activates_ability": { "exhaust": true } }, "this_turn": "once", "effects": [{ "copy_spell": { "of": { "triggering": "ability" }, "new_targets": true } }] } }` |
| "When you next cast a Lesson spell this turn, copy it" | the same with `{ "cast": { "spell": { "spell": { "subtypes": ["lesson"] } } } }` and `"of": { "triggering": "object" }` |
| "Whenever a creature you control attacking causes a triggered ability of that creature to trigger, … copy that ability" | trigger `{ "ability_triggers": { "subject": { "each": "creature", "controller": "you" }, "cause": "attacks" } }`, `copy_spell` of `{ "triggering": "ability" }` (nothing to copy once it left the stack) |
| "Whenever a creature you control boasts" (CR 702.142b) | `{ "activates_ability": { "boast": true } }` |
| "Whenever this creature becomes tapped to pay a teamwork cost" | `{ "becomes_tapped": { "for": "teamwork" } }` (it triggers once the spell is cast) |
| "you may copy it. If you do, those spells gain wither" | `copy_spell` with `"except": { "keywords": ["wither"] }`, then `{ "grant": { "keywords": ["wither"], "to": { "triggering": "object" } } }` (a spell on the stack can gain keywords) |
| "Instant and sorcery spells you cast from your hand have cascade" | ability `{ "spell_keywords": { "spells": { "spell": { "any_of": ["instant", "sorcery"] } }, "from": "hand", "keywords": ["cascade"] } }` |
| "search your library for up to X basic land cards with different names" | `{ "search_library": { "for": { "supertypes": ["basic"], "types": ["land"] }, "count": "x", "different_names": true } }` |
| "search your library for a creature card, put it into your graveyard, then shuffle" | `{ "search_library": { "for": { "types": ["creature"] }, "put": "graveyard" } }` |
| "search your library for a card, then shuffle and put that card on top" | `{ "search_library": { "put": "library_top" } }` (one card; add `"reveal": true` if it's revealed) |
| "an artifact card with mana value equal to 1 plus the sacrificed artifact's mana value" | `"for": { "types": ["artifact"], "mana_value": { "equal": { "plus": [{ "sacrificed": "mana_value" }, 1] } } }` |
| "The first time you flip one or more coins each turn, those coins come up heads and you win those flips" (CR 705.3) | ability `"first_flips_win"` |
| "Roll a d20" / "roll two six-sided dice" (CR 706) | `{ "roll_dice": { "sides": 20 } }` / `{ "roll_dice": { "amount": 2 } }`; the total is `{ "this_way": n }` (a results table is effects with an `if` on it) |

```json
{ "name": "Example Echo Drillmaster", "mana_cost": "{2}{R}", "types": ["creature"], "subtypes": ["goblin"],
  "power": 2, "toughness": 2,
  "abilities": [
    { "triggered": { "when": { "attacks": {} }, "effects": [{ "deal_damage": { "amount": 1, "to": "each_opponent" } }] } },
    { "triggered": { "when": { "ability_triggers": { "subject": { "each": "creature", "controller": "you" }, "cause": "attacks" } },
                     "effects": [{ "may": { "effects": [{ "copy_spell": { "of": { "triggering": "ability" } } }] } }] } }] }
```

### 4.29 Paradigm, foretell, suspend, hideaway, devour, meld and computed endure

| Oracle text | Data |
| --- | --- |
| "Paradigm" (CR 702.192a) | `"keywords": ["paradigm"]` on an instant or sorcery: as it finishes resolving it's exiled; the first time a spell you control with its name resolves this game, at the beginning of each of your precombat main phases you create a copy of the card in exile and may cast it without paying its mana cost (an `effect_choice` of `{type: "cast"}` or `"done"`) |
| "Foretell {2}{R}" (CR 702.143a) | ability `{ "foretell": { "cost": "{2}{R}" } }`: during your turn the priority option `{type: "special_action", object: id, ability: ref}` pays {2} and exiles it face down; on a later turn it's cast from exile with `via: "alt:<ref>"`; condition `{ "cast_with": "foretell" }` |
| "Plot {1}{R}" (CR 702.170a) | ability `{ "plot": { "cost": "{1}{R}" } }`: in your main phase with an empty stack the priority option `{type: "special_action", object: id, ability: ref}` pays the cost and exiles it face up; on a later turn it's cast from exile without paying its mana cost with `via: "plotted"`, at sorcery timing even for an instant |
| "Exile target spell. It becomes plotted." / "it becomes plotted" for an exiled card (CR 702.170c) | effect `{ "plot": { "to": { "target": 0 } } }` (or `{ "result": n }` for a card an earlier effect exiled) |
| "Suspend 3—{2}{W}" (CR 702.62a) | ability `{ "suspend": { "amount": 3, "cost": "{2}{W}" } }`: the special action exiles it with three time counters whenever you could begin to cast it |
| "exile it with four time counters on it. If it doesn't have suspend, it gains suspend" | effect `{ "suspend": { "to": …, "amount": 4 } }` (a spell, a card or a permanent); a card that has suspend from the start is `"keywords": ["suspend"]` |
| suspended cards (CR 702.62b) | automatic: at the beginning of its owner's upkeep a time counter is removed; when the last is removed they may play it without paying its mana cost (`effect_choice` `{type: "cast"}` / `{type: "play_land"}`), and a creature spell cast this way has haste while they control it |
| "Hideaway 4" (CR 702.75a) | ability `{ "hideaway": { "amount": 4 } }`: the exiled card is `"exiled_with"` the permanent, face down, and only its controller may look at it |
| "You may play the exiled card without paying its mana cost" | `{ "cast_free": { "to": "exiled_with", "play": true } }` (`play: true` also plays a land, on your turn with a land play left, CR 305.2a, 305.3) |
| "look at the top N cards, exile one face down" | `{ "dig": { "amount": N, "put": "exile", "face_down": true, "link": true } }` (`link`: exiled with the source) |
| "Devour land 3" (CR 702.82c) / "Devour 2" | ability `{ "devour": { "amount": 3, "each": "land" } }` / `{ "devour": { "amount": 2 } }`: as it enters, `enter_choice` `{type: "devour", object: id}` picks permanents one at a time, then `{type: "done"}`; it enters with N +1/+1 counters for each and remembers how many it devoured |
| Meld cards (CR 713) | `"layout": "meld"`, `"faces": [front, combined back face]`; both cards of the pair carry the same back face (e.g. Ragnarok, Divine Deliverance on Fang and on Vanille). The back face is up only on the melded permanent; when it leaves the battlefield both cards go to the new zone (CR 713.8) |
| "if you both own and control this and a creature named Fang, …, exile them, then meld them" (CR 701.42a) | condition `{ "meld_with": "Fang, Fearless l'Cie" }`; effect `{ "meld": { "with": "Fang, Fearless l'Cie" } }` (cards that don't form a meld pair stay exiled, CR 701.42c) |
| "endures X" / "endures X, where X is the number of counters on this creature" (CR 701.63a) | `{ "endure": { "amount": "x" } }` / `{ "endure": { "amount": { "counters": { "of": "self" } } } }`: the Spirit token is X/X |
| "Proliferate X times, where X is the number of planeswalker types among planeswalkers you control" | `{ "proliferate": { "amount": { "distinct_planeswalker_types": { "each": "planeswalker", "controller": "you" } } } }` |

```json
{ "name": "Example Lesson of Embers", "mana_cost": "{2}{R}", "types": ["sorcery"], "subtypes": ["lesson"],
  "keywords": ["paradigm"],
  "abilities": [{ "spell": { "targets": ["any_target"],
                             "effects": [{ "deal_damage": { "amount": 2, "to": { "target": 0 } } }] } },
                { "foretell": { "cost": "{1}{R}" } }] }
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

To play-test a whole folder of cards (every `.json` file below it, each a card or an
array of cards), use `--verify`. It validates every card, builds random decks that
together include each valid card, plays rules-monitored games with them, and reports
invalid cards, cards never used in play (cast, played, activated, triggered or
resolved), and any rules finding or engine error with its seed. Exit code 1 means
something needs a look; `--json` prints the report as JSON.

```sh
bundle exec exe/enjine --verify cards/ --games 20 --seed 1
```

From Ruby (`require "enjine/verify"`, then `Enjine::Verify.new(dir, games:, seed:).run`
returns the same report as a Hash).

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
