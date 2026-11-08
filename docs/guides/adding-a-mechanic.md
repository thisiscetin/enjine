# Adding a mechanic

A mechanic is a **primitive**: a small class that registers itself under a name
that card data can reference. The categories are `type`, `supertype`, `subtype`,
`keyword`, `ability`, `cost`, `effect` and `filter`.

## Checklist

1. **Read the rules.** Find the CR section (pinned version in `lib/enjine/version.rb`)
   and decide which primitive category the mechanic belongs to. Check
   `docs/MECHANICS_COVERAGE.md` for its milestone and priority.
2. **Write the primitive** in `lib/enjine/mechanics/<category>/…`:

   ```ruby
   module Enjine::Mechanics::Effects
     class Mill < Effect
       primitive :effect, :mill,
                 description: "Each referenced player mills `amount` cards.",
                 rules: %w[701.17a],
                 params: { "amount" => "integer", "to" => "selector" },
                 example: { "mill" => { "amount" => 2, "to" => "each_opponent" } }

       def apply(engine, ctx)
         players(engine, ctx).each do |i|
           amount.times { (id = engine.player(i).library.first) && engine.move!(id, :graveyard, reason: "mill") }
         end
       end
     end
   end
   ```

   - `build(params, errors, path, **)` validates the data and pushes path-prefixed
     errors (the `Effect` base class already handles `amount` and `to`).
   - Change state **only** through engine methods that emit events (`move!`,
     `deal_damage!`, `add_counters!`, `change_life!`, `tap!`, …).
   - If the mechanic needs new state, add it to `State`, `State#to_h`,
     `Snapshot.build` and `Snapshot.validate`, plus `View` if players can see it.
     The fuzzer will catch anything you forget.
3. **Regenerate the docs:** `bundle exec rake docs`. The docs spec fails until you do.
4. **Test at three levels:**
   - **Unit** (`spec/unit`): data validation and error paths.
   - **Integration** (`spec/integration`): a `build_game` scenario, then legal
     options, then a decision, then the resulting state and events. Cite the rule
     numbers in the example names.
   - **End-to-end:** add a card using the mechanic to `lib/enjine/card_pool/core.json`
     so the fuzzer (`rake fuzz`) plays it in thousands of random positions.
5. `bundle exec rake` (specs, coverage gate and RuboCop) must pass.

## Where things live

| You need | Look at |
| --- | --- |
| A new card type's timing or placement rules | `mechanics/types/` (`permanent?`, `instant_speed?`, `validate`) |
| A new kind of thing to do while holding priority | `lib/enjine/actions/` + `Actions.register` |
| A new kind of question for a player | `lib/enjine/decisions/` + `Decisions.register` |
| Turn-structure hooks | `lib/enjine/steps.rb` |
| P/T and other characteristics (layers) | `lib/enjine/engine/characteristics.rb` |
| State-based actions | `lib/enjine/engine/damage.rb` (`check_permanent_state_based_actions!`) |
