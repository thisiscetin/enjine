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
   - **In a set file** `lib/enjine/sets/<code>.json` (or your own `--sets-dir`), as
     the same object plus optional `"rarity": "common"` and
     `"printing": { "set": "trk", "number": "12" }`.
     The deck builder and collections read set files. A set with an invalid card fails
     to load and names the card and the error.
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
| `name` | yes | string | Unique. Its slug becomes the card id: `"Jace, the Mind Sculptor"` → `jace_the_mind_sculptor`. Two different definitions with the same name in one game raise `CatalogConflict`. |
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

`produce` is a string of mana symbols: `"{G}"`, `"{C}{C}"`. "Add one mana of any
color" is written as one mana ability per color (`{W}`, `{U}`, ...), and "add two
mana of any one color" as one per color producing `{W}{W}`, `{U}{U}`, ... (the same
decisions, no new rules). A mana ability whose amount varies ("add X mana") is not
supported yet.

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
| "Human", "non-Doctor" | `{ "creature": { "subtypes": ["human"] } }`, `{ "creature": { "not_subtypes": ["doctor"] } }` |
| "legendary", "nonlegendary" | `{ "creature": { "supertypes": ["legendary"] } }`, `{ "creature": { "not_supertypes": ["legendary"] } }` |
| "token", "nontoken" | `{ "creature": { "token": true } }`, `{ "creature": { "token": false } }` |
| "with a counter on it", "with a +1/+1 counter on it" | `{ "creature": { "counters": true } }`, `{ "creature": { "counters": "+1/+1" } }` |
| "modified" (CR 700.9) | `{ "creature": { "modified": true } }` |
| "attacking", "tapped" | `{ "creature": { "attacking": true } }`, `{ "creature": { "tapped": true } }` |
| "land, or creature with power 6 or greater" | `{ "one_of": [{ "permanent": { "any_of": ["land"] } }, { "creature": { "power": { "at_least": 6 } } }] }` |
| "noncreature spell" | `{ "spell": { "not": ["creature"] } }` |

"Target creature with flying" (keyword restrictions) is not supported yet.

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

Not supported yet: Auras that enchant players, Equipment that enters attached or
equips for a non-mana cost, and granted triggered or activated abilities ("equipped
creature has 'Whenever …'").

### 4.9 Station cards, Sagas and other set mechanics

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
- **A card castable from its owner's graveyard or exile**:
  `{ "play_from": { "zone": "graveyard" } }`; add `"enters_with": { "finality": 1 }`
  when a permanent spell cast that way gets a finality counter.
- **A permanent's permission** for its controller's own cards: give `cards` a card
  spec. Casting an artifact spell from the top of the library once per turn (on your
  own turns) is `{ "play_from": { "zone": "library_top", "cards": { "types":
  ["artifact"] }, "once_each_turn": true } }`; playing lands from the top uses
  `"cards": { "types": ["land"] }, "play": "play"`. Seeing the top card of your library
  at all times (CR 401.5) is the ability `"look_at_top"`.
- **Impulse draw**: `exile_top` (or `exile_until` with `"until": "nonland"`) followed by
  `{ "play_permission": { "to": { "result": 0 }, "duration": "end_of_your_next_turn" } }`
  (`end_of_turn` for the current turn only, `while_exiled` for as long as the cards stay
  in exile). `not_types: ["land"]` keeps only the nonland card an exile-until found;
  `"choose": "one_per_owner"` with `"for": { "types": ["land"] }` makes the controller
  pick one matching card per owner among the exiled ones.
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
